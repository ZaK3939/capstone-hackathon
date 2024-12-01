// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IInsuredHook} from "./interfaces/IInsuredHook.sol";
import {IInsuranceVault} from "./interfaces/IInsuranceVault.sol";
import {IHookRegistry} from "./interfaces/IHookRegistry.sol";
import {IUniGuardServiceManager} from "uniguard-avs/contracts/src/interfaces/IUniGuardServiceManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract HookRegistry is IHookRegistry, Ownable {
    // State variables
    struct HookInfo {
        address developer;
        uint256 usdcDeposit;
        bool isActive;
        uint256 riskScore;
        mapping(PoolId => bool) isPaused;
    }

    IERC20 public immutable USDC;
    IInsuranceVault public vault;
    IUniGuardServiceManager public serviceManager;
    uint256 public constant MINIMUM_DEPOSIT = 10_000 * 1e6; // 10,000 USDC
    bool public isVaultSet;

    mapping(address => HookInfo) public hooks;
    mapping(address => bool) public operators;
    uint256 public operatorCount;

    constructor(address _usdc, address _insuranceVault) {
        USDC = IERC20(_usdc);
        vault = IInsuranceVault(_insuranceVault);
        _transferOwnership(msg.sender);
    }

    bool public isServiceManagerSet;

    function setServiceManager(address _serviceManager) external {
        require(!isServiceManagerSet, "ServiceManager already set");
        require(_serviceManager != address(0), "Invalid ServiceManager address");
        serviceManager = IUniGuardServiceManager(_serviceManager);
        isServiceManagerSet = true;
    }

    // Add setVault function
    function setVault(address _vault) external {
        require(!isVaultSet, "Vault already set");
        vault = IInsuranceVault(_vault);
        isVaultSet = true;
    }

    // Hook Management
    function registerHook(address hook, uint256 usdcAmount) external {
        if (usdcAmount < MINIMUM_DEPOSIT) revert InvalidDeposit();
        if (hooks[hook].developer != address(0)) revert HookAlreadyRegistered();

        // Transfer USDC from developer to registry
        require(USDC.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");

        // Initialize hook info
        HookInfo storage info = hooks[hook];
        info.developer = msg.sender;
        info.usdcDeposit = usdcAmount;
        info.isActive = true;
        info.riskScore = 0;

        // First register hook in vault
        vault.registerHook(hook);

        // Then deposit USDC to vault
        USDC.approve(address(vault), usdcAmount);
        vault.depositUSDC(hook, usdcAmount);

        emit HookRegistered(hook, msg.sender, usdcAmount);
    }

    function pauseHook(address hook, PoolId poolId) external {
        if (!isOperatorApproved(msg.sender)) revert NotAuthorized();
        if (hooks[hook].developer == address(0)) revert HookNotRegistered();

        hooks[hook].isPaused[poolId] = true;
        IInsuredHook(hook).pause(poolId);

        emit HookPaused(hook, poolId);
    }

    function updateRiskScore(address hook, uint256 score) external {
        if (!isOperatorApproved(msg.sender)) revert NotAuthorized();
        if (hooks[hook].developer == address(0)) revert HookNotRegistered();
        hooks[hook].riskScore = score;
        emit RiskScoreUpdated(hook, score);
    }

    // View Functions
    function getHookInfo(address hook)
        external
        view
        returns (address developer, uint256 usdcDeposit, bool isActive, uint256 riskScore)
    {
        HookInfo storage info = hooks[hook];
        return (info.developer, info.usdcDeposit, info.isActive, info.riskScore);
    }

    function isPoolPaused(address hook, PoolId poolId) external view returns (bool) {
        return hooks[hook].isPaused[poolId];
    }

    function registerOperator(address operator) external onlyOwner {
        require(operator != address(0), "Invalid operator address");
        require(!operators[operator], "Already registered");

        operators[operator] = true;
        operatorCount++;
        emit OperatorRegistered(operator);
    }

    function removeOperator(address operator) external onlyOwner {
        require(operators[operator], "Not registered");

        operators[operator] = false;
        operatorCount--;
        emit OperatorRemoved(operator);
    }

    function isOperatorApproved(address operator) public view returns (bool) {
        return operators[operator];
    }

    // Hook Status Getters
    function getDepositedAmount(address hook) external view returns (uint256) {
        return hooks[hook].usdcDeposit;
    }

    function getDeveloper(address hook) external view returns (address) {
        return hooks[hook].developer;
    }

    function getRiskScore(address hook) external view returns (uint256) {
        return hooks[hook].riskScore;
    }
}
