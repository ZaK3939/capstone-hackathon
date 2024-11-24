// MockInsuranceVault.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IInsuranceVault} from "../../src/interfaces/IInsuranceVault.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

contract MockInsuranceVault is IInsuranceVault {
    mapping(address => uint256) public usdcBalances;
    mapping(address => uint256) public uniBalances;
    mapping(address => StakeInfo) public stakeInfos;
    VaultInfo public vaultInfo;

    function depositUSDC(uint256 amount) external {
        usdcBalances[msg.sender] += amount;
        vaultInfo.totalUSDCDeposited += amount;
    }

    function withdrawUSDC(uint256 amount) external {
        require(usdcBalances[msg.sender] >= amount, "Insufficient balance");
        usdcBalances[msg.sender] -= amount;
        vaultInfo.totalUSDCDeposited -= amount;
    }

    function supplyToMorpho(uint256 amount) external {
        // Mock implementation
    }

    function withdrawFromMorpho(uint256 amount) external {
        // Mock implementation
    }

    function stakeUNI(uint256 amount) external {
        uniBalances[msg.sender] += amount;
        vaultInfo.totalUNIStaked += amount;
    }

    function unstakeUNI(uint256 amount) external {
        require(uniBalances[msg.sender] >= amount, "Insufficient UNI balance");
        uniBalances[msg.sender] -= amount;
        vaultInfo.totalUNIStaked -= amount;
    }

    function claimRewards() external returns (uint256) {
        return 0; // Mock implementation
    }

    function processCompensation(address hook, PoolId poolId, uint256 lossAmount)
        external
        returns (uint256 usdcPaid, uint256 uniPaid)
    {
        uint256 availableUSDC = usdcBalances[hook];
        if (availableUSDC >= lossAmount) {
            return (lossAmount, 0);
        }
        return (availableUSDC, lossAmount - availableUSDC);
    }

    function getVaultInfo() external view returns (VaultInfo memory) {
        return vaultInfo;
    }

    function getStakeInfo(address user) external view returns (StakeInfo memory) {
        return stakeInfos[user];
    }

    function getMorphoYield() external view returns (uint256) {
        return 0; // Mock implementation
    }

    function getAvailableUSDC() external view returns (uint256) {
        return vaultInfo.totalUSDCDeposited;
    }
}
