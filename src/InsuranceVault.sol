// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IInsuranceVault} from "./interfaces/IInsuranceVault.sol";
import {IHookRegistry} from "./interfaces/IHookRegistry.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console2} from "forge-std/Console2.sol";

contract InsuranceVault is IInsuranceVault, Ownable {
    // State variables
    IHookRegistry public immutable registry;
    IERC20 public immutable USDC;
    IERC20 public immutable UNI;
    // Struct for brevis

    struct Victim {
        address victim;
        address hook;
        uint256 amount;
        bool processed;
    }

    // Morpho mock state
    uint256 public morphoBalance;
    uint256 public morphoYield;

    // Hook and staking state
    mapping(address => uint256) public usdcBalances; // hook => balance
    mapping(address => uint256) public uniBalances; // staker => balance
    mapping(address => StakeInfo) public stakeInfos; // staker => info
    mapping(address => bool) public registeredHooks; // hook => isRegistered
    mapping(address => mapping(address => uint256)) public hookStakes; // hook => staker => amount
    mapping(address => uint256) public insuranceFees; // hook => accumulated insurance fees
    mapping(address => uint256) public hookToProposalId; // hook => proposalId
    mapping(address => Victim) public victimDatas; // hook => victim data
    VaultInfo public vaultInfo;

    uint256 public constant VOTE_THRESHOLD_PERCENTAGE = 51; // 51% of total stake required to pass proposal
    uint256 public constant INSURANCE_FEE_PERCENTAGE = 20; // 20% of swap fees go to insurance
    uint256 public constant STAKER_REWARD_PERCENTAGE = 80; // 80% of swap fees go to stakers
    uint256 public constant COOLDOWN_PERIOD = 72 hours;

    mapping(uint256 => InsolvencyProposal) public proposals;
    uint256 public proposalCount;

    constructor(address _registry, address _usdc, address _uni) {
        registry = IHookRegistry(_registry);
        USDC = IERC20(_usdc);
        UNI = IERC20(_uni);
        _transferOwnership(msg.sender);
        proposalCount = 1;
    }

    // Hook Registration
    function registerHook(address hook) external {
        require(msg.sender == address(registry), "Only registry");
        require(!registeredHooks[hook], "Hook already registered");
        registeredHooks[hook] = true;
        emit HookRegistered(hook);
    }

    // USDC Operations
    function depositUSDC(address hook, uint256 amount) external {
        require(msg.sender == address(registry), "Only registry");
        require(registeredHooks[hook], "Hook not registered");

        USDC.transferFrom(msg.sender, address(this), amount);
        usdcBalances[hook] += amount;
        vaultInfo.totalUSDCDeposited += amount;

        supplyToMorpho(amount);
        emit USDCDeposited(hook, amount);
    }

    function withdrawUSDC(uint256 amount) external {
        require(usdcBalances[msg.sender] >= amount, "Insufficient balance");

        if (USDC.balanceOf(address(this)) < amount) {
            withdrawFromMorpho(amount);
        }

        usdcBalances[msg.sender] -= amount;
        vaultInfo.totalUSDCDeposited -= amount;
        USDC.transfer(msg.sender, amount);
    }

    // Morpho Integration
    function supplyToMorpho(uint256 amount) public {
        require(msg.sender == address(this) || msg.sender == address(registry), "Unauthorized");
        morphoBalance += amount;
    }

    function withdrawFromMorpho(uint256 amount) public {
        require(msg.sender == address(this) || msg.sender == address(registry), "Unauthorized");
        require(morphoBalance >= amount, "Insufficient Morpho balance");
        morphoBalance -= amount;
    }

    // Swap Fee Management
    function receiveSwapFee(address hook) external payable {
        require(msg.sender == hook, "Only hook can send fees");
        require(registeredHooks[hook], "Hook not registered");

        uint256 amount = msg.value;
        emit SwapFeeReceived(hook, amount);

        // Split fee between insurance and staker rewards
        uint256 insuranceFee = (amount * INSURANCE_FEE_PERCENTAGE) / 100;
        uint256 stakerReward = (amount * STAKER_REWARD_PERCENTAGE) / 100;

        insuranceFees[hook] += insuranceFee;
        vaultInfo.totalFees += stakerReward;

        emit InsuranceFeeAccumulated(hook, insuranceFee);
        emit StakerRewardAccumulated(hook, stakerReward);
    }

    // UNI Staking
    function stakeUNI(uint256 amount, address hook) external {
        require(amount > 0, "Cannot stake 0");
        require(registeredHooks[hook], "Hook not registered");

        UNI.transferFrom(msg.sender, address(this), amount);

        StakeInfo storage info = stakeInfos[msg.sender];
        info.amount += amount;
        info.lastRewardTime = block.timestamp;
        info.rewardDebt += _calculateRewards(msg.sender);

        uniBalances[msg.sender] += amount;
        hookStakes[hook][msg.sender] += amount;
        vaultInfo.totalUNIStaked += amount;

        emit UNIStaked(msg.sender, amount);
    }

    function unstakeUNI(uint256 amount, address hook) external {
        StakeInfo storage info = stakeInfos[msg.sender];
        require(hookStakes[hook][msg.sender] >= amount, "Insufficient hook stake");
        require(block.timestamp >= info.lastRewardTime + COOLDOWN_PERIOD, "Cooldown period active");

        // Claim pending rewards before unstaking
        _claimRewards(msg.sender);

        info.amount -= amount;
        uniBalances[msg.sender] -= amount;
        hookStakes[hook][msg.sender] -= amount;
        vaultInfo.totalUNIStaked -= amount;

        UNI.transfer(msg.sender, amount);
    }

    function claimRewards() external returns (uint256) {
        return _claimRewards(msg.sender);
    }

    // Insolvency Proposal
    function proposeInsolvency(address hook) external returns (uint256) {
        require(msg.sender == address(registry), "Only registry can propose");
        require(registeredHooks[hook], "Hook not registered");
        require(registry.isHookPaused(hook), "Hook must be paused");

        uint256 proposalId = proposalCount++;
        InsolvencyProposal storage proposal = proposals[proposalId];
        proposal.hook = hook;
        proposal.totalStake = _getTotalHookStake(hook);
        console2.log("proposaled hook", hook);
        emit InsolvencyProposalCreated(proposalId, hook);
        return proposalId;
    }

    function castVote(uint256 proposalId) external {
        InsolvencyProposal storage proposal = proposals[proposalId];
        require(!proposal.executed, "Already executed");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(uniBalances[msg.sender] > 0, "Must be UNI staker");

        uint256 weight = hookStakes[proposal.hook][msg.sender];
        require(weight > 0, "No stake in affected hook");

        proposal.forVotes += weight;
        proposal.hasVoted[msg.sender] = true;

        emit VoteCast(proposalId, msg.sender, weight);
    }

    function executeProposal(uint256 proposalId) external {
        require(msg.sender == address(registry), "Only registry can execute");
        InsolvencyProposal storage proposal = proposals[proposalId];
        require(!proposal.executed, "Already executed");
        require(proposal.forVotes * 100 >= proposal.totalStake * VOTE_THRESHOLD_PERCENTAGE, "Vote threshold not met");

        proposal.executed = true;
        proposal.passed = true;

        _processCompensationPrepare(proposal.hook);
        console2.log("proposal.hook in execute", proposal.hook);
        console2.log("proposalId in execute", proposalId);
        hookToProposalId[proposal.hook] = proposalId;

        emit ProposalExecuted(proposalId, true);
    }

    function cancelProposal(uint256 proposalId) external {
        require(msg.sender == address(registry), "Only registry can cancel");
        InsolvencyProposal storage proposal = proposals[proposalId];
        require(!proposal.executed, "Already executed");

        proposal.executed = true;
        proposal.passed = false;

        emit ProposalCancelled(proposalId);
    }

    function _processCompensationPrepare(address hook) internal {
        require(registeredHooks[hook], "Hook not registered");

        // First Layer: Initial Deposit
        uint256 depositAmount = usdcBalances[hook];

        // Second Layer: Accumulated Insurance Fees
        uint256 feeAmount = insuranceFees[hook];

        uint256 totalCompensation = depositAmount + feeAmount;

        if (depositAmount > 0) {
            if (USDC.balanceOf(address(this)) < depositAmount) {
                withdrawFromMorpho(depositAmount);
            }
            usdcBalances[hook] = 0;
        }

        if (feeAmount > 0) {
            insuranceFees[hook] = 0;
        }

        emit CompensationProcessed(hook, totalCompensation);
    }

    // need to impl modifier for brevis
    function setVictims(address[] calldata victims, address[] calldata hooks, uint256[] calldata amounts) external {
        require(victims.length == hooks.length && victims.length == amounts.length, "Invalid input lengths");

        for (uint256 i = 0; i < victims.length; i++) {
            require(victims[i] != address(0), "Invalid victim address");
            require(hooks[i] != address(0), "Invalid hook address");
            require(amounts[i] > 0, "Invalid amount");

            victimDatas[victims[i]] = Victim({victim: victims[i], hook: hooks[i], amount: amounts[i], processed: false});

            emit VictimRegistered(victims[i], hooks[i], amounts[i]);
        }
    }

    function compensateVictim(address victim) external {
        Victim storage victimData = victimDatas[victim];
        console2.log("victimData.victim", victimData.victim);
        console2.log("victimData.hook", victimData.hook);
        require(victimData.victim != address(0), "Victim not registered");
        require(!victimData.processed, "Compensation already processed");

        address hook = victimData.hook;
        // Check if there's an approved proposal for this hook
        console2.log("hookToProposalId[hook]", hookToProposalId[hook]);
        console2.log("proposals[hookToProposalId[hook]].passed", proposals[hookToProposalId[hook]].passed);
        require(hookToProposalId[hook] != 0, "No approved proposal for hook");
        require(proposals[hookToProposalId[hook]].passed, "Proposal not passed");

        uint256 compensationAmount = victimData.amount;

        // Transfer compensation to victim
        require(USDC.transfer(victim, compensationAmount), "Compensation transfer failed");

        victimData.processed = true;

        emit CompensationProcessed(victim, compensationAmount);
    }

    function _claimRewards(address staker) internal returns (uint256) {
        StakeInfo storage info = stakeInfos[msg.sender];
        require(info.amount > 0, "No stake found");

        uint256 pending = _calculateRewards(staker);
        if (pending > 0) {
            info.rewardDebt = 0;
            info.lastRewardTime = block.timestamp;
            // Transfer ETH instead of USDC
            (bool success,) = staker.call{value: pending}("");
            require(success, "ETH transfer failed");
            emit RewardsDistributed(staker, pending);
        }
        return pending;
    }

    function _calculateRewards(address staker) internal view returns (uint256) {
        StakeInfo memory info = stakeInfos[staker];
        if (info.amount == 0 || vaultInfo.totalUNIStaked == 0) return 0;

        uint256 totalRewards = vaultInfo.totalFees + morphoYield;
        if (totalRewards == 0) return 0;

        uint256 stakerShare = (info.amount * totalRewards) / vaultInfo.totalUNIStaked;
        return stakerShare - info.rewardDebt;
    }

    function _getTotalHookStake(address hook) internal view returns (uint256) {
        return vaultInfo.totalUNIStaked;
    }

    // View Functions
    function getProposal(uint256 proposalId)
        external
        view
        returns (address hook, uint256 forVotes, uint256 totalStake, bool executed, bool passed)
    {
        InsolvencyProposal storage proposal = proposals[proposalId];
        return (proposal.hook, proposal.forVotes, proposal.totalStake, proposal.executed, proposal.passed);
    }

    function getVaultInfo() external view returns (VaultInfo memory) {
        return vaultInfo;
    }

    function getDepositedAmount(address hook) external view returns (uint256) {
        return usdcBalances[hook];
    }

    function getStakeInfo(address user) external view returns (StakeInfo memory) {
        return stakeInfos[user];
    }

    function getMorphoYield() external view returns (uint256) {
        return morphoYield;
    }

    function getAvailableUSDC() external view returns (uint256) {
        return USDC.balanceOf(address(this)) + morphoBalance;
    }

    function getHookStake(address hook, address staker) external view returns (uint256) {
        return hookStakes[hook][staker];
    }

    function getInsuranceFee(address hook) external view returns (uint256) {
        return insuranceFees[hook];
    }

    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return proposals[proposalId].hasVoted[voter];
    }

    receive() external payable {}
}
