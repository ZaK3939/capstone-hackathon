// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IInsuredHook} from "./interfaces/IInsuredHook.sol";
import {IHookRegistry} from "./interfaces/IHookRegistry.sol";
import {IInsuranceVault} from "./interfaces/IInsuranceVault.sol";

contract InsuredHook is BaseHook, IInsuredHook {
    using PoolIdLibrary for PoolKey;

    // Constants
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant FEE_RATE = 10; // 0.1% = 10/10000

    // State variables
    IHookRegistry public immutable registry;
    IInsuranceVault public immutable insuranceVault;
    mapping(PoolId => uint256) public swapVolumes;
    mapping(PoolId => bool) public isPaused;

    constructor(IPoolManager _poolManager, address _registry, address _insuranceVault) BaseHook(_poolManager) {
        registry = IHookRegistry(_registry);
        insuranceVault = IInsuranceVault(_insuranceVault);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        if (isPaused[key.toId()]) revert PoolPaused();
        if (registry.isPoolPaused(address(this), key.toId())) revert PausedByRegistry();

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) external override returns (bytes4, int128) {
        uint256 volume = calculateSwapVolume(params, delta);
        swapVolumes[key.toId()] += volume;

        uint256 fee = (volume * FEE_RATE) / FEE_DENOMINATOR;
        if (fee > 0) {
            emit FeesCollected(key.toId(), fee);
            // Fee transfer logic will be implemented
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    function pause(PoolId poolId) external {
        if (msg.sender != address(registry)) revert OnlyRegistry();
        isPaused[poolId] = true;
        emit HookPaused(poolId);
    }

    function calculateSwapVolume(IPoolManager.SwapParams calldata params, BalanceDelta delta)
        internal
        pure
        returns (uint256)
    {
        int256 amount;
        if (params.zeroForOne) {
            amount = int256(delta.amount0());
        } else {
            amount = int256(delta.amount1());
        }
        return amount >= 0 ? uint256(amount) : uint256(-amount);
    }

    function getFeeRate() external pure returns (uint256) {
        return FEE_RATE;
    }

    function getRegistry() external view override returns (address) {
        return address(registry);
    }
}
