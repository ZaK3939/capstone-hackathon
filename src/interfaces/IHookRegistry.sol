// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolId} from "v4-core/src/types/PoolId.sol";

interface IHookRegistry {
    struct HookInfo {
        address developer;
        uint256 usdcDeposit;
        bool isActive;
        uint256 riskScore;
        mapping(PoolId => bool) isPaused;
    }

    event HookRegistered(address indexed hook, address indexed developer, uint256 deposit);
    event HookPaused(address indexed hook, PoolId indexed poolId);
    event RiskScoreUpdated(address indexed hook, uint256 score);
    
    function registerHook(address hook, uint256 usdcAmount) external;
    function pauseHook(address hook, PoolId poolId) external;
    function updateRiskScore(address hook, uint256 score) external;
    function getHookInfo(address hook) external view returns (
        address developer,
        uint256 usdcDeposit,
        bool isActive,
        uint256 riskScore
    );
    function isPoolPaused(address hook, PoolId poolId) external view returns (bool);
    function isOperatorApproved(address operator) external view returns (bool);
}