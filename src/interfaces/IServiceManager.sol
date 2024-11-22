// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolId} from "v4-core/src/types/PoolId.sol";

interface IServiceManager {
   struct Task {
       address hook;                // Target hook address
       PoolId poolId;              // Target pool id
       uint32 taskCreatedBlock;    // Block number when task was created
       bytes32 metricsHash;        // Hash of metrics data
       bool isCompleted;           // Task completion status
       uint256 riskScore;          // Calculated risk score
   }

   struct Metrics {
       uint256 txCount;            // Number of transactions
       uint256 gasUsed;            // Gas consumption
       uint256 tvlChange;          // TVL delta
       uint256 priceImpact;        // Price impact score
       uint256 blockNumber;        // Block number of metrics
   }

   event TaskCreated(uint256 indexed taskId, address indexed hook, PoolId indexed poolId);
   event TaskCompleted(uint256 indexed taskId, uint256 riskScore);
   event MetricsSubmitted(uint256 indexed taskId, address indexed operator);
   event OperatorRegistered(address indexed operator, uint256 stake);
   event RiskScoreUpdated(address indexed hook, PoolId indexed poolId, uint256 score);

   // Task Management
   function createTask(address hook, PoolId poolId) external returns (uint256 taskId);
   function submitMetrics(
       uint256 taskId,
       Metrics calldata metrics,
       bytes calldata signature
   ) external;

   // Operator Management
   function registerOperator(uint256 stake) external;
   function removeOperator() external;
   function slashOperator(address operator) external;

   // Risk Assessment
   function calculateRiskScore(Metrics calldata metrics) external pure returns (uint256);
   function triggerEmergencyPause(address hook, PoolId poolId) external;

   // View Functions
   function getTask(uint256 taskId) external view returns (Task memory);
   function getActiveOperators() external view returns (address[] memory);
   function isOperator(address account) external view returns (bool);
   function getOperatorStake(address operator) external view returns (uint256);
}