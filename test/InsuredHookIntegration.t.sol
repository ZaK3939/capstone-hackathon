// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {InsuredHook} from "../src/InsuredHook.sol";
import {HookRegistry} from "../src/HookRegistry.sol";
import {InsuranceVault} from "../src/InsuranceVault.sol";
import {BrevisHandler} from "../src/BrevisHandler.sol";
import {IInsuredHook} from "../src/interfaces/IInsuredHook.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {MockBrevisRequest} from "./mock/MockBrevisRequest.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {UniGuardServiceManager} from "uniguard-avs/contracts/src/UniGuardServiceManager.sol";
import {MockServiceManager} from "./mock/MockServiceManager.sol";
import {console2} from "forge-std/Console2.sol";

contract InsuredHookIntegrationTest is Test, Fixtures {
    InsuredHook public hook;
    HookRegistry public registry;
    InsuranceVault public vault;
    MockServiceManager public mockServiceManager;
    BrevisHandler brevisHandler;
    MockBrevisRequest mockBrevisRequest;

    MockERC20 public usdc;
    MockERC20 public uni;
    PoolId public poolId;

    address public developer;
    address public uniStaker;
    address public uniStaker2;
    address public victim1;
    address public operator;

    uint256 constant INITIAL_USDC = 100_000 * 1e6; // 100,000 USDC
    uint256 constant INITIAL_UNI = 100_000 * 1e18; // 100,000 UNI
    uint256 constant HOOK_DEPOSIT = 10_000 * 1e6; // 10,000 USDC
    uint256 constant UNI_STAKE = 1_000 * 1e18; // 1,000 UNI

    bytes circuitOutput;

    event HookRegistered(address indexed hook, address indexed developer, uint256 deposit);
    event HookActivated(address indexed hook);
    event UNIStaked(address indexed staker, uint256 amount);
    event RiskScoreUpdated(address indexed hook, uint256 score);
    event HookPaused(address indexed hook);
    event InsolvencyProposalCreated(uint256 indexed proposalId, address indexed hook, PoolId poolId);
    event VoteCast(uint256 indexed proposalId, address indexed voter, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId, bool passed);

    bytes32 vkHash = 0x1234000000000000000000000000000000000000000000000000000000000000;

    function setUp() public {
        // Setup accounts
        developer = makeAddr("developer");
        uniStaker = makeAddr("uniStaker");
        uniStaker2 = makeAddr("uniStaker2");
        victim1 = makeAddr("victim1");
        operator = makeAddr("operator");

        // Deploy mock tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        uni = new MockERC20("UNI", "UNI", 18);

        // Deploy base contracts
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        // Deploy core contracts
        registry = new HookRegistry(address(usdc), address(this));
        vault = new InsuranceVault(address(registry), address(usdc), address(uni));
        mockServiceManager = new MockServiceManager();

        // Link contracts
        registry.setVault(address(vault));
        registry.setServiceManager(address(mockServiceManager));

        // Setup hook
        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144));
        bytes memory constructorArgs = abi.encode(manager, address(registry), address(vault));
        deployCodeTo("InsuredHook.sol:InsuredHook", constructorArgs, flags);
        hook = InsuredHook(flags);

        // Setup pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Setup initial balances
        usdc.mint(developer, INITIAL_USDC);
        uni.mint(uniStaker, INITIAL_UNI);
        uni.mint(uniStaker2, INITIAL_UNI);

        // Approvals
        vm.startPrank(developer);
        usdc.approve(address(registry), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(uniStaker);
        uni.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(uniStaker2);
        uni.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        // Setup BrevisHandler
        brevisHandler = new BrevisHandler(address(mockBrevisRequest), address(vault));
        brevisHandler.setVkHash(vkHash); // Set a dummy vkHash
    }

    function test_HookRegistrationFlow() public {
        vm.startPrank(developer);
        vm.expectEmit(true, true, false, true);
        emit HookRegistered(address(hook), developer, HOOK_DEPOSIT);
        registry.registerHook(address(hook), HOOK_DEPOSIT);

        (address registeredDev, uint256 deposit, bool isActive, bool isPaused, uint256 riskScore) =
            registry.getHookInfo(address(hook));

        assertEq(registeredDev, developer);
        assertEq(deposit, HOOK_DEPOSIT);
        assertFalse(isActive);
        assertFalse(isPaused);
        assertEq(riskScore, 0);
        assertEq(vault.getDepositedAmount(address(hook)), HOOK_DEPOSIT);
        vm.stopPrank();
    }

    function test_UniStakingFlow() public {
        vm.prank(developer);
        registry.registerHook(address(hook), HOOK_DEPOSIT);

        uint256 initialUniBalance = uni.balanceOf(uniStaker);
        uint256 initialVaultBalance = uni.balanceOf(address(vault));

        vm.startPrank(uniStaker);
        vm.expectEmit(true, false, false, true);
        emit UNIStaked(uniStaker, UNI_STAKE);
        vault.stakeUNI(UNI_STAKE, address(hook));

        assertEq(uni.balanceOf(uniStaker), initialUniBalance - UNI_STAKE);
        assertEq(uni.balanceOf(address(vault)), initialVaultBalance + UNI_STAKE);
        assertEq(vault.uniBalances(uniStaker), UNI_STAKE);
        assertEq(vault.getHookStake(address(hook), uniStaker), UNI_STAKE);
        vm.stopPrank();

        assertFalse(registry.isHookPaused(address(hook)));
    }

    function test_RiskMonitoringAndPauseFlow() public {
        vm.prank(developer);
        registry.registerHook(address(hook), HOOK_DEPOSIT);

        vm.prank(uniStaker);
        vault.stakeUNI(UNI_STAKE, address(hook));

        vm.startPrank(address(mockServiceManager));
        vm.expectEmit(true, false, false, true);
        emit RiskScoreUpdated(address(hook), 80);
        registry.updateRiskScore(address(hook), 80);

        vm.expectEmit(true, false, false, true);
        emit HookPaused(address(hook));
        registry.pauseHook(address(hook));

        assertTrue(registry.isHookPaused(address(hook)));
        vm.stopPrank();
    }

    function test_InsolvencyFlow() public {
        // Setup initial state
        vm.prank(developer);
        registry.registerHook(address(hook), HOOK_DEPOSIT);

        // Setup stakers
        vm.prank(uniStaker);
        vault.stakeUNI(UNI_STAKE, address(hook));
        vm.prank(uniStaker2);
        vault.stakeUNI(UNI_STAKE, address(hook));

        // Pause hook
        vm.startPrank(address(mockServiceManager));
        registry.updateRiskScore(address(hook), 80);
        vm.stopPrank();

        // Create insolvency proposal
        vm.startPrank(address(registry));
        uint256 proposalId = vault.proposeInsolvency(address(hook));

        // Vote on proposal
        vm.startPrank(uniStaker);
        vault.castVote(proposalId);
        vm.stopPrank();

        vm.startPrank(uniStaker2);
        vault.castVote(proposalId);
        vm.stopPrank();

        // Set up victim data through Brevis
        address[] memory victims = new address[](1);
        address[] memory hooks = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        victims[0] = address(victim1);
        console2.log("Victim address: ", victims[0]);
        hooks[0] = address(hook);
        amounts[0] = 10;

        circuitOutput = abi.encodePacked(bytes20(victims[0]), bytes20(hooks[0]), bytes32(amounts[0]));
        vm.startPrank(address(mockBrevisRequest));
        brevisHandler.brevisCallback(vkHash, circuitOutput);
        vm.stopPrank();

        // Execute proposal
        vm.startPrank(address(registry));
        vault.executeProposal(proposalId);

        // Verify proposal state
        (,,, bool executed, bool passed) = vault.getProposal(proposalId);
        assertTrue(executed);
        assertTrue(passed);

        // Verify compensation effects
        assertTrue(vault.usdcBalances(address(hook)) < HOOK_DEPOSIT);

        // Verify proposal is recorded for the hook
        assertEq(vault.hookToProposalId(address(hook)), proposalId);

        // Test victim compensation
        uint256 initialBalance = usdc.balanceOf(address(victim1));

        vault.compensateVictim(victims[0]);

        // Verify victim compensation
        assertEq(usdc.balanceOf(address(victim1)), initialBalance + 10);

        // Verify victim data is marked as processed
        (,,, bool processed) = vault.victimDatas(address(victim1));
        assertTrue(processed);

        vm.stopPrank();
    }

    function test_CompleteLifecycle() public {
        // Registration
        vm.prank(developer);
        registry.registerHook(address(hook), HOOK_DEPOSIT);

        // Staking
        vm.prank(uniStaker);
        vault.stakeUNI(UNI_STAKE, address(hook));
        vm.prank(uniStaker2);
        vault.stakeUNI(UNI_STAKE, address(hook));

        // Risk Detection and Pause
        vm.startPrank(address(mockServiceManager));
        registry.updateRiskScore(address(hook), 80);
        vm.stopPrank();

        // Insolvency Handling
        vm.startPrank(address(registry));
        uint256 proposalId = vault.proposeInsolvency(address(hook));

        // Voting
        vm.startPrank(uniStaker);
        vault.castVote(proposalId);
        vm.stopPrank();

        vm.startPrank(uniStaker2);
        vault.castVote(proposalId);
        vm.stopPrank();

        // Execute proposal
        vm.startPrank(address(registry));
        vault.executeProposal(proposalId);

        // Final state verification
        (,, bool isActive, bool isPaused,) = registry.getHookInfo(address(hook));
        assertTrue(isPaused);
        assertFalse(isActive);

        // Verify proposal state
        (,,, bool executed, bool passed) = vault.getProposal(proposalId);
        assertTrue(executed);
        assertTrue(passed);
    }
}
