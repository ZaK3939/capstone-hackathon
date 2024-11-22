// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface IInsuranceVault {
   struct VaultInfo {
       uint256 totalUSDCDeposited;    // 預けられているUSDC総額
       uint256 totalUNIStaked;        // ステークされているUNI総額
       uint256 totalFees;             // 累積手数料
   }

   struct StakeInfo {
       uint256 amount;                // ステーク量
       uint256 lastRewardTime;        // 最終報酬時間
       uint256 rewardDebt;            // 未払い報酬
   }

   event USDCDeposited(address indexed hook, uint256 amount);
   event UNIStaked(address indexed user, uint256 amount);
   event RewardsDistributed(address indexed user, uint256 amount);
   event CompensationProcessed(
       address indexed hook, 
       PoolId indexed poolId, 
       uint256 usdcAmount, 
       uint256 uniAmount
   );

   // USDC関連
   function depositUSDC(uint256 amount) external;
   function withdrawUSDC(uint256 amount) external;
   function supplyToMorpho(uint256 amount) external;
   function withdrawFromMorpho(uint256 amount) external;

   // UNIステーキング
   function stakeUNI(uint256 amount) external;
   function unstakeUNI(uint256 amount) external;
   function claimRewards() external returns (uint256);

   // 保険処理
   function processCompensation(
       address hook, 
       PoolId poolId,
       uint256 lossAmount
   ) external returns (uint256 usdcPaid, uint256 uniPaid);

   // View functions
   function getVaultInfo() external view returns (VaultInfo memory);
   function getStakeInfo(address user) external view returns (StakeInfo memory);
   function getMorphoYield() external view returns (uint256);
   function getAvailableUSDC() external view returns (uint256);
}