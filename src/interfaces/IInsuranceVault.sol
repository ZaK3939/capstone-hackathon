// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface IInsuranceVault {
    // Structs
    struct VaultInfo {
        uint256 totalUSDCDeposited;
        uint256 totalUNIStaked;
        uint256 totalFees;
    }

    struct StakeInfo {
        uint256 amount;
        uint256 lastRewardTime;
        uint256 rewardDebt;
    }

    struct InsolvencyProposal {
        address hook;
        uint256 forVotes;
        uint256 totalStake;
        bool executed;
        bool passed;
        mapping(address => bool) hasVoted;
    }

    // Events
    event SwapFeeReceived(address indexed hook, uint256 amount);
    event InsuranceFeeAccumulated(address indexed hook, uint256 amount);
    event StakerRewardAccumulated(address indexed hook, uint256 amount);
    event RewardsDistributed(address indexed staker, uint256 amount);
    event HookRegistered(address indexed hook);
    event USDCDeposited(address indexed hook, uint256 amount);
    event UNIStaked(address indexed staker, uint256 amount);
    event CompensationProcessed(address indexed hook, uint256 totalAmount);
    event InsolvencyProposalCreated(uint256 indexed proposalId, address indexed hook);
    event VoteCast(uint256 indexed proposalId, address indexed voter, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId, bool passed);
    event ProposalCancelled(uint256 indexed proposalId);
    event VictimRegistered(address indexed victim, address indexed hook, uint256 amount);

    // Hook Registration
    function registerHook(address hook) external;

    // USDC Management
    function depositUSDC(address hook, uint256 amount) external;
    function withdrawUSDC(uint256 amount) external;
    function supplyToMorpho(uint256 amount) external;
    function withdrawFromMorpho(uint256 amount) external;

    // Swap Fee Management
    function receiveSwapFee(address hook) external payable;

    // UNI Staking
    function stakeUNI(uint256 amount, address hook) external;
    function unstakeUNI(uint256 amount, address hook) external;
    function claimRewards() external returns (uint256);

    // Insolvency Proposal
    function proposeInsolvency(address hook) external returns (uint256);
    function castVote(uint256 proposalId) external;
    function cancelProposal(uint256 proposalId) external;
    function setVictims(address[] memory victims, address[] memory hooks, uint256[] memory amounts) external;

    // View Functions
    function getProposal(uint256 proposalId)
        external
        view
        returns (address hook, uint256 forVotes, uint256 totalStake, bool executed, bool passed);
    function getVaultInfo() external view returns (VaultInfo memory);
    function getDepositedAmount(address hook) external view returns (uint256);
    function getStakeInfo(address user) external view returns (StakeInfo memory);
    function getMorphoYield() external view returns (uint256);
    function getAvailableUSDC() external view returns (uint256);
    function getHookStake(address hook, address staker) external view returns (uint256);
    function getInsuranceFee(address hook) external view returns (uint256);
    function hasVoted(uint256 proposalId, address voter) external view returns (bool);
}
