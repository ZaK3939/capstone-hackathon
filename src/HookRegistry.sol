// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IInsuredHook} from "./interfaces/IInsuredHook.sol";
import {IInsuranceVault} from "./interfaces/IInsuranceVault.sol";
import {IHookRegistry} from "./interfaces/IHookRegistry.sol";
import {IUniGuardServiceManager} from "uniguard-avs/contracts/src/interfaces/IUniGuardServiceManager.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console2} from "forge-std/console2.sol";

contract HookRegistry is IHookRegistry, Ownable {
    using LibString for address;

    struct HookInfo {
        address developer;
        uint256 usdcDeposit;
        bool isActive;
        bool isPaused;
        uint256 riskScore;
    }

    IERC20 public immutable USDC;
    IInsuranceVault public vault;
    IUniGuardServiceManager public serviceManager;
    uint256 public constant MINIMUM_DEPOSIT = 10_000 * 1e6; // 10,000 USDC
    uint256 public riskThreshold = 80;
    bool public isVaultSet;
    bool public isServiceManagerSet;

    mapping(address => HookInfo) public hooks;

    constructor(address _usdc, address _insuranceVault) {
        USDC = IERC20(_usdc);
        vault = IInsuranceVault(_insuranceVault);
        _transferOwnership(msg.sender);
    }

    function setServiceManager(address _serviceManager) external onlyOwner {
        require(!isServiceManagerSet, "ServiceManager already set");
        require(_serviceManager != address(0), "Invalid ServiceManager address");
        serviceManager = IUniGuardServiceManager(_serviceManager);
        isServiceManagerSet = true;
        emit ServiceManagerSet(_serviceManager);
    }

    function setRiskThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold > 0 && _threshold <= 100, "Invalid threshold value");
        riskThreshold = _threshold;
        emit RiskThresholdUpdated(_threshold);
    }

    function setVault(address _vault) external onlyOwner {
        require(!isVaultSet, "Vault already set");
        vault = IInsuranceVault(_vault);
        isVaultSet = true;
    }

    function registerHook(address hook, uint256 usdcAmount) external {
        if (usdcAmount < MINIMUM_DEPOSIT) revert InvalidDeposit();
        if (hooks[hook].developer != address(0)) revert HookAlreadyRegistered();

        require(USDC.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");

        HookInfo storage info = hooks[hook];
        info.developer = msg.sender;
        info.usdcDeposit = usdcAmount;
        info.isActive = false; // Initially inactive until UNI stake is confirmed
        info.isPaused = false;
        info.riskScore = 0;

        vault.registerHook(hook);

        USDC.approve(address(vault), usdcAmount);
        vault.depositUSDC(hook, usdcAmount);

        serviceManager.createNewTask(hook.toHexString());

        emit HookRegistered(hook, msg.sender, usdcAmount);
    }

    function activateHook(address hook) external {
        require(msg.sender == address(vault), "Only Vault can activate");
        require(hooks[hook].developer != address(0), "Hook not registered");
        require(!hooks[hook].isActive, "Hook already active");

        hooks[hook].isActive = true;
        emit HookActivated(hook);
    }

    function deactivateHook(address hook) external {
        require(msg.sender == address(vault), "Only Vault can deactivate");
        require(hooks[hook].isActive, "Hook not active");

        hooks[hook].isActive = false;
        emit HookDeactivated(hook);
    }

    function pauseHook(address hook) public {
        require(msg.sender == address(serviceManager), "Only ServiceManager can pause");
        if (hooks[hook].developer == address(0)) revert HookNotRegistered();

        hooks[hook].isPaused = true;
        IInsuredHook(hook).pause();

        emit HookPaused(hook);
    }

    function unpauseHook(address hook) external {
        require(msg.sender == address(serviceManager), "Only ServiceManager can unpause");
        if (hooks[hook].developer == address(0)) revert HookNotRegistered();
        if (!hooks[hook].isPaused) revert HookNotPaused();

        hooks[hook].isPaused = false;
        IInsuredHook(hook).unpause();

        emit HookUnpaused(hook);
    }

    function updateRiskScore(address hook, uint256 score) external {
        require(msg.sender == address(serviceManager), "Only ServiceManager can update");
        hooks[hook].riskScore = score;
        emit RiskScoreUpdated(hook, score);

        if (score >= riskThreshold) {
            pauseHook(hook);
        }
    }

    // View Functions
    function getHookInfo(address hook)
        external
        view
        returns (address developer, uint256 usdcDeposit, bool isActive, bool isPaused, uint256 riskScore)
    {
        HookInfo storage info = hooks[hook];
        return (info.developer, info.usdcDeposit, info.isActive, info.isPaused, info.riskScore);
    }

    function getDepositedAmount(address hook) external view returns (uint256) {
        return hooks[hook].usdcDeposit;
    }

    function getDeveloper(address hook) external view returns (address) {
        return hooks[hook].developer;
    }

    function getRiskScore(address hook) external view returns (uint256) {
        return hooks[hook].riskScore;
    }

    function isHookPaused(address hook) external view returns (bool) {
        return hooks[hook].isPaused;
    }
}
