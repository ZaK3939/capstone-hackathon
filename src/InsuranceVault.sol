// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IInsuranceVault} from "./interfaces/IInsuranceVault.sol";
import {IHookRegistry} from "./interfaces/IHookRegistry.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract InsuranceVault is IInsuranceVault, Ownable {
    // State variables
    IHookRegistry public immutable registry;
    IERC20 public immutable USDC;
    IERC20 public immutable UNI;

    // Morpho mock state
    uint256 public morphoBalance;
    uint256 public morphoYield;

    // Hook and staking state
    mapping(address => uint256) public usdcBalances; // hook => balance
    mapping(address => uint256) public uniBalances; // staker => balance
    mapping(address => StakeInfo) public stakeInfos; // staker => info
    mapping(address => bool) public registeredHooks; // hook => isRegistered
    mapping(address => mapping(address => uint256)) public hookStakes; // hook => staker => amount
    VaultInfo public vaultInfo;

    constructor(address _registry, address _usdc, address _uni) {
        registry = IHookRegistry(_registry);
        USDC = IERC20(_usdc);
        UNI = IERC20(_uni);
        _transferOwnership(msg.sender);
    }

    // Hook Registration
    function registerHook(address hook) external {
        require(msg.sender == address(registry), "Only registry");
        require(!registeredHooks[hook], "Hook already registered");
        registeredHooks[hook] = true;
        emit HookRegistered(hook);
    }

    function depositUSDC(address hook, uint256 amount) external {
        require(msg.sender == address(registry), "Only registry");
        require(registeredHooks[hook], "Hook not registered");

        USDC.transferFrom(msg.sender, address(this), amount);
        usdcBalances[hook] += amount;
        vaultInfo.totalUSDCDeposited += amount;

        // Auto supply to Morpho
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

    // Morpho Integration (Mock)
    function supplyToMorpho(uint256 amount) public {
        require(msg.sender == address(this) || msg.sender == address(registry), "Unauthorized");
        morphoBalance += amount;
    }

    function withdrawFromMorpho(uint256 amount) public {
        require(msg.sender == address(this) || msg.sender == address(registry), "Unauthorized");
        require(morphoBalance >= amount, "Insufficient Morpho balance");
        morphoBalance -= amount;
    }

    // UNI Staking
    function stakeUNI(uint256 amount, address hook) external {
        require(amount > 0, "Cannot stake 0");
        require(registeredHooks[hook], "Hook not registered");

        UNI.transferFrom(msg.sender, address(this), amount);

        StakeInfo storage info = stakeInfos[msg.sender];
        info.amount += amount;
        info.lastRewardTime = block.timestamp;

        uniBalances[msg.sender] += amount;
        hookStakes[hook][msg.sender] += amount;
        vaultInfo.totalUNIStaked += amount;

        emit UNIStaked(msg.sender, amount);
    }

    function unstakeUNI(uint256 amount, address hook) external {
        StakeInfo storage info = stakeInfos[msg.sender];
        require(hookStakes[hook][msg.sender] >= amount, "Insufficient hook stake");
        require(block.timestamp >= info.lastRewardTime + 72 hours, "Cooldown period active");

        info.amount -= amount;
        uniBalances[msg.sender] -= amount;
        hookStakes[hook][msg.sender] -= amount;
        vaultInfo.totalUNIStaked -= amount;

        UNI.transfer(msg.sender, amount);
    }

    function claimRewards() external returns (uint256) {
        StakeInfo storage info = stakeInfos[msg.sender];
        require(info.amount > 0, "No stake found");

        uint256 pending = _calculateRewards(msg.sender);
        if (pending > 0) {
            info.rewardDebt = 0;
            info.lastRewardTime = block.timestamp;
            USDC.transfer(msg.sender, pending);
            emit RewardsDistributed(msg.sender, pending);
        }
        return pending;
    }

    // Insurance Processing
    function processCompensation(address hook, PoolId poolId, uint256 lossAmount)
        external
        returns (uint256 usdcPaid, uint256 uniPaid)
    {
        require(msg.sender == address(registry), "Only registry");
        require(registeredHooks[hook], "Hook not registered");
        require(lossAmount > 0, "Invalid loss amount");

        // Primary layer: USDC
        uint256 availableUSDC = usdcBalances[hook];
        if (availableUSDC >= lossAmount) {
            if (USDC.balanceOf(address(this)) < lossAmount) {
                withdrawFromMorpho(lossAmount);
            }
            usdcBalances[hook] -= lossAmount;
            USDC.transfer(msg.sender, lossAmount);
            emit CompensationProcessed(hook, poolId, lossAmount, 0);
            return (lossAmount, 0);
        }

        // Secondary layer: UNI
        usdcPaid = availableUSDC;
        uniPaid = lossAmount - usdcPaid;

        if (usdcPaid > 0) {
            if (USDC.balanceOf(address(this)) < usdcPaid) {
                withdrawFromMorpho(usdcPaid);
            }
            usdcBalances[hook] = 0;
            USDC.transfer(msg.sender, usdcPaid);
        }

        if (uniPaid > 0) {
            require(vaultInfo.totalUNIStaked > 0, "No UNI staked");
            _processUNICompensation(hook, uniPaid);
        }

        emit CompensationProcessed(hook, poolId, usdcPaid, uniPaid);
        return (usdcPaid, uniPaid);
    }

    // View Functions
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

    // Internal Functions
    function _calculateRewards(address staker) internal view returns (uint256) {
        StakeInfo memory info = stakeInfos[staker];
        if (info.amount == 0) return 0;

        uint256 stakerShare = (info.amount * (vaultInfo.totalFees + morphoYield)) / vaultInfo.totalUNIStaked;
        return stakerShare - info.rewardDebt;
    }

    function _processUNICompensation(address hook, uint256 uniAmount) internal {
        uint256 totalStaked = vaultInfo.totalUNIStaked;
        vaultInfo.totalUNIStaked -= uniAmount;

        uint256 remainingUni = uniAmount;
        address[] memory stakers = _getHookStakers(hook);

        for (uint256 i = 0; i < stakers.length && remainingUni > 0; i++) {
            address staker = stakers[i];
            uint256 stakerShare = (hookStakes[hook][staker] * uniAmount) / totalStaked;

            if (stakerShare > 0) {
                hookStakes[hook][staker] -= stakerShare;
                uniBalances[staker] -= stakerShare;
                remainingUni -= stakerShare;
            }
        }
    }

    function _getHookStakers(address hook) internal view returns (address[] memory) {
        // このメソッドの実装が必要
        // hookに紐づくステーカーのリストを返す
    }
}
