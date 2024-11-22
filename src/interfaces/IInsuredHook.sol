// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

interface IInsuredHook {
    // Custom errors
    error PoolPaused();
    error PausedByRegistry();
    error OnlyRegistry();

    // Events
    event HookPaused(PoolId indexed poolId);
    event FeesCollected(PoolId indexed poolId, uint256 amount);

    // View functions
    function isPaused(PoolId poolId) external view returns (bool);
    function getFeeRate() external pure returns (uint256);
    function getRegistry() external view returns (address);
    function swapVolumes(PoolId poolId) external view returns (uint256);

    // State changing functions
    function pause(PoolId poolId) external;

    // Hook functions
}
