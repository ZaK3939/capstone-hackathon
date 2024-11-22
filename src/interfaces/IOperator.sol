// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolId} from "v4-core/src/types/PoolId.sol";

interface IOperator {
   struct OperatorInfo {
       uint256 stake;              // Operator's staked amount
       uint256 taskCount;          // Number of tasks completed
       uint256 lastUpdateBlock;    // Last update block number
       bool isActive;              // Active status
   }

   struct MetricsSubmission {
       uint256 taskId;             // Reference task ID
       bytes32 metricsHash;        // Hash of submitted metrics
       uint256 timestamp;          // Submission timestamp
       bool confirmed;             // Confirmation status
   }

   event MetricsSubmitted(
       address indexed operator,
       uint256 indexed taskId,
       bytes32 metricsHash
   );
   event ConsensusReached(
       uint256 indexed taskId,
       uint256 riskScore
   );
   event OperatorSlashed(
       address indexed operator,
       uint256 amount,
       string reason
   );

   // Metrics Submission
   function submitMetrics(
       uint256 taskId,
       bytes calldata metrics,
       bytes calldata signature
   ) external returns (bool);

   // Consensus Functions
   function validateSubmission(
       uint256 taskId,
       bytes32 metricsHash
   ) external returns (bool);

   function checkConsensus(uint256 taskId) external view returns (
       bool reached,
       uint256 consensusScore
   );

   // Operator Management
   function activateOperator() external;
   function deactivateOperator() external;
   function updateStake(uint256 newStake) external;

   // View Functions
   function getOperatorInfo(address operator) external view returns (OperatorInfo memory);
   function getSubmission(uint256 taskId) external view returns (MetricsSubmission memory);
   function getActiveTaskCount() external view returns (uint256);
}