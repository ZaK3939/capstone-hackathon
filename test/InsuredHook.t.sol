// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {InsuredHook} from "../src/InsuredHook.sol";
import {IHookRegistry} from "../src/interfaces/IHookRegistry.sol";
import {IInsuranceVault} from "../src/interfaces/IInsuranceVault.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";

import {IInsuredHook} from "../src/interfaces/IInsuredHook.sol";

contract InsuredHookTest is Test, Fixtures {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using EasyPosm for IPositionManager;

    InsuredHook hook;
    PoolId poolId;
    MockRegistry registry;
    MockInsuranceVault vault;
    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        deployAndApprovePosm(manager);

        registry = new MockRegistry();
        vault = new MockInsuranceVault();

        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144));
        bytes memory constructorArgs = abi.encode(manager, address(registry), address(vault));
        deployCodeTo("InsuredHook.sol:InsuredHook", constructorArgs, flags);
        hook = InsuredHook(flags);

        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function testFeeCollection() public {
        bool zeroForOne = true;
        int256 amountSpecified = -1e18;
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        assertEq(int256(swapDelta.amount0()), amountSpecified);
        assertEq(hook.swapVolumes(poolId), uint256(-amountSpecified));
    }

    function testPauseByRegistry() public {
        vm.prank(address(registry));
        hook.pause(poolId);

        assertTrue(hook.isPaused(poolId));

        bool zeroForOne = true;
        int256 amountSpecified = -1e18;
        vm.expectRevert();
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
    }
}

contract MockRegistry is IHookRegistry {
    mapping(address => mapping(PoolId => bool)) public isPaused;
    mapping(address => address) public developers;
    mapping(address => uint256) public deposits;
    mapping(address => bool) public isActive;
    mapping(address => uint256) public riskScores;
    mapping(address => bool) public approvedOperators;

    function registerHook(address hook, uint256 usdcAmount) external {
        developers[hook] = msg.sender;
        deposits[hook] = usdcAmount;
        isActive[hook] = true;
    }

    function pauseHook(address hook, PoolId poolId) external {
        isPaused[hook][poolId] = true;
    }

    function updateRiskScore(address hook, uint256 score) external {
        riskScores[hook] = score;
    }

    function getHookInfo(address hook)
        external
        view
        returns (address developer, uint256 usdcDeposit, bool active, uint256 riskScore)
    {
        return (developers[hook], deposits[hook], isActive[hook], riskScores[hook]);
    }

    function isPoolPaused(address hook, PoolId poolId) external view returns (bool) {
        return isPaused[hook][poolId];
    }

    function isOperatorApproved(address operator) external view returns (bool) {
        return approvedOperators[operator];
    }
}

contract MockInsuranceVault is IInsuranceVault {
    mapping(address => uint256) public usdcBalances;
    mapping(address => uint256) public uniBalances;
    mapping(address => StakeInfo) public stakeInfos;
    VaultInfo public vaultInfo;
    uint256 public morphoYield;
    uint256 public availableUsdc;

    function depositUSDC(uint256 amount) external {
        usdcBalances[msg.sender] += amount;
        vaultInfo.totalUSDCDeposited += amount;
    }

    function withdrawUSDC(uint256 amount) external {
        require(usdcBalances[msg.sender] >= amount);
        usdcBalances[msg.sender] -= amount;
        vaultInfo.totalUSDCDeposited -= amount;
    }

    function supplyToMorpho(uint256 amount) external {
        availableUsdc -= amount;
    }

    function withdrawFromMorpho(uint256 amount) external {
        availableUsdc += amount;
    }

    function stakeUNI(uint256 amount) external {
        uniBalances[msg.sender] += amount;
        vaultInfo.totalUNIStaked += amount;
    }

    function unstakeUNI(uint256 amount) external {
        require(uniBalances[msg.sender] >= amount);
        uniBalances[msg.sender] -= amount;
        vaultInfo.totalUNIStaked -= amount;
    }

    function claimRewards() external returns (uint256) {
        return morphoYield / 100;
    }

    function processCompensation(address hook, PoolId poolId, uint256 lossAmount)
        external
        returns (uint256 usdcPaid, uint256 uniPaid)
    {
        uint256 availableUSDC = usdcBalances[hook];
        if (availableUSDC >= lossAmount) {
            return (lossAmount, 0);
        }
        return (availableUSDC, lossAmount - availableUSDC);
    }

    function getVaultInfo() external view returns (VaultInfo memory) {
        return vaultInfo;
    }

    function getStakeInfo(address user) external view returns (StakeInfo memory) {
        return stakeInfos[user];
    }

    function getMorphoYield() external view returns (uint256) {
        return morphoYield;
    }

    function getAvailableUSDC() external view returns (uint256) {
        return availableUsdc;
    }
}
