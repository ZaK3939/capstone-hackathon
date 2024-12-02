// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IInsuredHook {
    // Custom errors
    error OnlyRegistry();
    error PausedByRegistry();

    // Events
    event FeesCollected(uint256 indexed poolId, uint256 amount);
    event HookPaused(address indexed hook);
    event HookUnpaused(address indexed hook);

    // View functions
    function isPaused() external view returns (bool);
    function getFeeRate() external pure returns (uint256);
    function getRegistry() external view returns (address);

    // State changing functions
    function pause() external;
    function unpause() external;
}
