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

// import {IHookRegistry} from "../src/interfaces/IHookRegistry.sol";
import {IInsuranceVault} from "../src/interfaces/IInsuranceVault.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";

import {InsuredHook} from "../src/InsuredHook.sol";
import {HookRegistry} from "../src/HookRegistry.sol";
import {InsuranceVault} from "../src/InsuranceVault.sol";

import {MockERC20} from "./mock/MockERC20.sol";
import {IInsuredHook} from "../src/interfaces/IInsuredHook.sol";

contract InsuredHookTest is Test, Fixtures {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using EasyPosm for IPositionManager;

    InsuredHook hook;
    PoolId poolId;
    HookRegistry registry;
    InsuranceVault vault;
    MockERC20 usdc;
    MockERC20 public uni;
    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        deployAndApprovePosm(manager);

        usdc = new MockERC20("USDC", "USDC", 6);
        registry = new HookRegistry(address(usdc), address(this)); // Temporary vault address
        vault = new InsuranceVault(address(registry), address(usdc), address(uni));
        // Update registry's vault address
        registry.setVault(address(vault));

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
        hook.pause();

        assertTrue(hook.isPaused());

        bool zeroForOne = true;
        int256 amountSpecified = -1e18;
        vm.expectRevert();
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
    }
}
