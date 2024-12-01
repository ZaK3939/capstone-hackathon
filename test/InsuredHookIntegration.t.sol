// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {InsuredHook} from "../src/InsuredHook.sol";
import {HookRegistry} from "../src/HookRegistry.sol";
import {InsuranceVault} from "../src/InsuranceVault.sol";
import {IInsuredHook} from "../src/interfaces/IInsuredHook.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {UniGuardServiceManager} from "uniguard-avs/contracts/src/UniGuardServiceManager.sol";
import {IUniGuardServiceManager} from "uniguard-avs/contracts/src/interfaces/IUniGuardServiceManager.sol";
// import {ECDSAStakeRegistry} from "uniguard-avs/contracts/lib/eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";

contract InsuredHookIntegrationTest is Test {
    InsuredHook hook;
    HookRegistry registry;
    InsuranceVault vault;
    UniGuardServiceManager serviceManager;
    MockERC20 usdc;
    MockERC20 uni;

    // Test constants
    uint256 constant INITIAL_DEPOSIT = 10000e6; // 10,000 USDC
    uint256 constant THRESHOLD_AMOUNT = 5000e6; // 5,000 USDC for testing

    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        uni = new MockERC20("UNI", "UNI", 18);

        // Deploy core contracts
        registry = new HookRegistry(address(usdc), address(this));
        vault = new InsuranceVault(address(registry), address(usdc), address(uni));
        serviceManager = new UniGuardServiceManager(address(registry));

        // Configure registry
        registry.setVault(address(vault));
        registry.setServiceManager(address(serviceManager));

        // Deploy hook
        hook = new InsuredHook(address(registry));

        // Mint initial tokens
        usdc.mint(address(this), INITIAL_DEPOSIT);
        uni.mint(address(this), 1000e18);
    }

    function testHookRegistration() public {
        // Step 1: Register hook
        usdc.approve(address(registry), INITIAL_DEPOSIT);
        registry.registerHook(address(hook), INITIAL_DEPOSIT);

        // Verify registration
        (address developer, uint256 deposit, bool active, uint256 riskScore) = registry.getHookInfo(address(hook));
        assertEq(developer, address(this));
        assertEq(deposit, INITIAL_DEPOSIT);
        assertTrue(active);
        assertEq(riskScore, 0);
    }

    function testAnomalyDetection() public {
        // Setup
        testHookRegistration();

        // Simulate anomaly detection
        bytes memory anomalyData = abi.encode("High gas usage detected");
        vm.prank(address(serviceManager));
        registry.updateRiskScore(address(hook), 80); // High risk score

        // Verify risk score update
        (,,, uint256 newRiskScore) = registry.getHookInfo(address(hook));
        assertEq(newRiskScore, 80);
    }

    function testHookPause() public {
        // Setup
        testHookRegistration();
        testAnomalyDetection();

        // Pause hook via registry
        bytes32 poolId = bytes32(uint256(1)); // Example pool ID
        vm.prank(address(registry));
        hook.pause(poolId);

        // Verify pause status
        assertTrue(hook.isPaused(poolId));
    }

    function testInsolvencyDetermination() public {
        // Setup
        testHookRegistration();
        testAnomalyDetection();
        testHookPause();

        // Simulate loss event
        uint256 lossAmount = THRESHOLD_AMOUNT;
        bytes32 poolId = bytes32(uint256(1));

        // Process compensation
        vm.prank(address(registry));
        (uint256 usdcPaid, uint256 uniPaid) = vault.processCompensation(address(hook), poolId, lossAmount);

        // Verify compensation
        assertEq(usdcPaid + uniPaid, lossAmount);
    }

    function testInsolvencyResolution() public {
        // Setup
        testHookRegistration();
        testAnomalyDetection();
        testHookPause();
        testInsolvencyDetermination();

        bytes32 poolId = bytes32(uint256(1));

        // Verify hook status after insolvency
        (,, bool active,) = registry.getHookInfo(address(hook));
        assertFalse(active);

        // Verify pool remains paused
        assertTrue(hook.isPaused(poolId));
    }
}
