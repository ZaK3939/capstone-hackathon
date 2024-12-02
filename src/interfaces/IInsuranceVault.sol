// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface IInsuranceVault {
    // Structs
    struct VaultInfo {
        uint256 totalUSDCDeposited; // Total USDC deposited
        uint256 totalUNIStaked; // Total UNI staked
        uint256 totalFees; // Total accumulated fees
    }

    struct StakeInfo {
        uint256 amount; // Staked amount
        uint256 lastRewardTime; // Last reward timestamp
        uint256 rewardDebt; // Pending rewards
    }

    // Events
    event USDCDeposited(address indexed hook, uint256 amount);
    event UNIStaked(address indexed user, uint256 amount);
    event RewardsDistributed(address indexed user, uint256 amount);
    event CompensationProcessed(address indexed hook, PoolId indexed poolId, uint256 usdcAmount, uint256 uniAmount);
    event HookRegistered(address indexed hook);

    // Hook Management
    function registerHook(address hook) external;

    // USDC Management
    function depositUSDC(address hook, uint256 amount) external;
    function withdrawUSDC(uint256 amount) external;
    function supplyToMorpho(uint256 amount) external;
    function withdrawFromMorpho(uint256 amount) external;

    // UNI Staking
    function stakeUNI(uint256 amount, address hook) external;
    function unstakeUNI(uint256 amount, address hook) external;
    function claimRewards() external returns (uint256);

    // Insurance Processing
    function processCompensation(address hook, PoolId poolId, uint256 lossAmount)
        external
        returns (uint256 usdcPaid, uint256 uniPaid);

    // View Functions
    function getVaultInfo() external view returns (VaultInfo memory);
    function getDepositedAmount(address hook) external view returns (uint256);
    function getStakeInfo(address user) external view returns (StakeInfo memory);
    function getMorphoYield() external view returns (uint256);
    function getAvailableUSDC() external view returns (uint256);
    function getHookStake(address hook, address staker) external view returns (uint256);
}
