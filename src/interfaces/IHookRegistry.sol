// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IInsuredHook} from "./IInsuredHook.sol";
import {IInsuranceVault} from "./IInsuranceVault.sol";

interface IHookRegistry {
    // Custom Errors
    error NotAuthorized();
    error InvalidDeposit();
    error HookNotRegistered();

    // Events
    event HookRegistered(address indexed hook, address indexed developer, uint256 deposit);
    event HookPaused(address indexed hook, PoolId indexed poolId);
    event RiskScoreUpdated(address indexed hook, uint256 score);
    event OperatorRegistered(address indexed operator);
    event OperatorRemoved(address indexed operator);

    // Hook Management
    function registerHook(address hook, uint256 usdcAmount) external;
    function pauseHook(address hook, PoolId poolId) external;
    function updateRiskScore(address hook, uint256 score) external;

    // View Functions
    function getHookInfo(address hook)
        external
        view
        returns (address developer, uint256 usdcDeposit, bool isActive, uint256 riskScore);
    function isPoolPaused(address hook, PoolId poolId) external view returns (bool);

    // Operator Management
    function registerOperator(address operator) external;
    function removeOperator(address operator) external;
    function isOperatorApproved(address operator) external view returns (bool);

    // Hook Status
    function getDepositedAmount(address hook) external view returns (uint256);
    function getDeveloper(address hook) external view returns (address);
    function getRiskScore(address hook) external view returns (uint256);
}
