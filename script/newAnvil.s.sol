// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Constants} from "v4-core/src/../test/utils/Constants.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {InsuredHook} from "../src/InsuredHook.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {EasyPosm} from "../test/utils/EasyPosm.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "../test/utils/forks/DeployPermit2.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPositionDescriptor} from "v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {HookRegistry} from "../src/HookRegistry.sol";
import {InsuranceVault} from "../src/InsuranceVault.sol";
import {IUniGuardServiceManager} from "uniguard-avs/contracts/src/interfaces/IUniGuardServiceManager.sol";

contract CounterScript is Script, DeployPermit2 {
    using EasyPosm for IPositionManager;

    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
    address public serviceManagerAddress;

    function setUp() public {
        // Read UniGuard AVS deployment data
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/hello-world/", vm.toString(block.chainid), ".json");

        string memory json = vm.readFile(path);
        serviceManagerAddress = abi.decode(vm.parseJson(json, ".addresses.uniGuardServiceManager"), (address));
    }

    function run() public {
        vm.startBroadcast(); // 単一のブロードキャストブロックを開始

        // プールマネージャーとトークンのデプロイ
        IPoolManager manager = deployPoolManager();
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        MockERC20 uni = new MockERC20("UNI", "UNI", 18);

        console2.log("serviceManagerAddress: %s", serviceManagerAddress);
        // レジストリとボールトのデプロイ
        HookRegistry registry = new HookRegistry(address(usdc), address(this));
        registry.setServiceManager(serviceManagerAddress);

        InsuranceVault vault = new InsuranceVault(address(registry), address(usdc), address(uni));
        console2.log("vault address: %s", address(vault));
        registry.setVault(address(vault));

        // InsuredHookのデプロイ
        uint160 permissions = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            permissions,
            type(InsuredHook).creationCode,
            abi.encode(manager, address(registry), address(vault))
        );
        console2.log("Hook address: %s", hookAddress);

        InsuredHook hook = new InsuredHook{salt: salt}(manager, address(registry), address(vault));
        console.log("InsuredHook address: %s", address(hook));
        require(address(hook) == hookAddress, "CounterScript: hook address mismatch");

        // トークンの初期設定
        usdc.mint(msg.sender, 100_000 * 1e6);
        usdc.approve(address(registry), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
        uint256 depositAmount = 10_000 * 1e6;
        registry.registerHook(address(hook), depositAmount);

        // 追加のヘルパーデプロイ
        IPositionManager posm = deployPosm(manager);
        (PoolModifyLiquidityTest lpRouter, PoolSwapTest swapRouter,) = deployRouters(manager);

        // テストライフサイクルの実行
        console2.log("Testing lifecycle");
        testLifecycle(manager, address(hook), posm, lpRouter, swapRouter);

        vm.stopBroadcast(); // 単一のブロードキャストブロックを終了
    }

    function deployPoolManager() internal returns (IPoolManager) {
        return IPoolManager(address(new PoolManager(address(0))));
    }

    function deployRouters(IPoolManager manager)
        internal
        returns (PoolModifyLiquidityTest lpRouter, PoolSwapTest swapRouter, PoolDonateTest donateRouter)
    {
        lpRouter = new PoolModifyLiquidityTest(manager);
        swapRouter = new PoolSwapTest(manager);
        donateRouter = new PoolDonateTest(manager);
    }

    function deployPosm(IPoolManager poolManager) public returns (IPositionManager) {
        anvilPermit2();
        return IPositionManager(
            new PositionManager(poolManager, permit2, 300_000, IPositionDescriptor(address(0)), IWETH9(address(0)))
        );
    }

    function approvePosmCurrency(IPositionManager posm, Currency currency) internal {
        IERC20(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(currency), address(posm), type(uint160).max, type(uint48).max);
    }

    function deployTokens() internal returns (MockERC20 token0, MockERC20 token1) {
        MockERC20 tokenA = new MockERC20("MockA", "A", 18);
        MockERC20 tokenB = new MockERC20("MockB", "B", 18);
        if (uint160(address(tokenA)) < uint160(address(tokenB))) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }
    }

    function testLifecycle(
        IPoolManager manager,
        address hook,
        IPositionManager posm,
        PoolModifyLiquidityTest lpRouter,
        PoolSwapTest swapRouter
    ) internal {
        (MockERC20 token0, MockERC20 token1) = deployTokens();
        token0.mint(msg.sender, 100_000 ether);
        token1.mint(msg.sender, 100_000 ether);

        bytes memory ZERO_BYTES = new bytes(0);

        int24 tickSpacing = 60;
        PoolKey memory poolKey =
            PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, tickSpacing, IHooks(hook));
        manager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        token0.approve(address(lpRouter), type(uint256).max);
        token1.approve(address(lpRouter), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);

        approvePosmCurrency(posm, Currency.wrap(address(token0)));
        approvePosmCurrency(posm, Currency.wrap(address(token1)));

        lpRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(tickSpacing), TickMath.maxUsableTick(tickSpacing), 100 ether, 0
            ),
            ZERO_BYTES
        );

        posm.mint(
            poolKey,
            TickMath.minUsableTick(tickSpacing),
            TickMath.maxUsableTick(tickSpacing),
            100e18,
            10_000e18,
            10_000e18,
            msg.sender,
            block.timestamp + 300,
            ZERO_BYTES
        );

        bool zeroForOne = true;
        int256 amountSpecified = 1 ether;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(poolKey, params, testSettings, ZERO_BYTES);
    }
}
