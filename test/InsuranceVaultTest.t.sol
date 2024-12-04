// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InsuranceVault} from "../src/InsuranceVault.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {HookRegistry} from "../src/HookRegistry.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IInsuranceVault} from "../src/interfaces/IInsuranceVault.sol";

contract InsuranceVaultTest is Test {
    InsuranceVault public vault;
    MockERC20 public usdc;
    MockERC20 public uni;
    address public registry;
    address public hook;
    address public staker;
    address public staker2;

    uint256 constant INITIAL_USDC = 100_000 * 1e6; // 100,000 USDC
    uint256 constant INITIAL_UNI = 100_000 * 1e18; // 100,000 UNI
    uint256 constant STAKE_AMOUNT = 1000 * 1e18; // 1,000 UNI

    event HookRegistered(address indexed hook);
    event USDCDeposited(address indexed hook, uint256 amount);
    event UNIStaked(address indexed staker, uint256 amount);
    event CompensationProcessed(address indexed hook, PoolId indexed poolId, uint256 usdcPaid);
    event SwapFeeReceived(address indexed hook, uint256 amount);
    event InsuranceFeeAccumulated(address indexed hook, uint256 amount);
    event StakerRewardAccumulated(address indexed hook, uint256 amount);
    event RewardsDistributed(address indexed staker, uint256 amount);
    event VoteCast(uint256 indexed proposalId, address indexed voter, uint256 weight);
    event InsolvencyProposalCreated(uint256 indexed proposalId, address indexed hook, PoolId poolId);
    event ProposalExecuted(uint256 indexed proposalId, bool passed);

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        uni = new MockERC20("UNI", "UNI", 18);

        registry = makeAddr("registry");
        hook = makeAddr("hook");
        staker = makeAddr("staker");
        staker2 = makeAddr("staker2");

        vault = new InsuranceVault(registry, address(usdc), address(uni));

        usdc.mint(address(registry), INITIAL_USDC);
        usdc.mint(address(vault), INITIAL_USDC);
        uni.mint(address(staker), INITIAL_UNI);
        uni.mint(address(staker2), INITIAL_UNI);
        uni.mint(address(vault), INITIAL_UNI);

        vm.startPrank(registry);
        usdc.approve(address(vault), type(uint256).max);
        // モックレジストリの設定
        vm.mockCall(registry, abi.encodeWithSignature("isHookPaused(address)"), abi.encode(true));
        vm.stopPrank();

        vm.prank(staker);
        uni.approve(address(vault), type(uint256).max);
        vm.prank(staker2);
        uni.approve(address(vault), type(uint256).max);
    }

    function testMainFlow() public {
        // Register hook
        vm.prank(registry);
        vault.registerHook(hook);
        assertTrue(vault.registeredHooks(hook));

        // Deposit USDC
        uint256 depositAmount = 10_000 * 1e6;
        vm.prank(registry);
        vault.depositUSDC(hook, depositAmount);
        assertEq(vault.usdcBalances(hook), depositAmount);

        // Stake UNI
        vm.startPrank(staker);
        vault.stakeUNI(STAKE_AMOUNT, hook);
        assertEq(vault.uniBalances(staker), STAKE_AMOUNT);
        assertEq(vault.getHookStake(hook, staker), STAKE_AMOUNT);
        vm.stopPrank();

        // Simulate swap fee
        uint256 swapFee = 1 ether;
        vm.deal(hook, swapFee);
        vm.prank(hook);
        vault.receiveSwapFee{value: swapFee}(hook);

        // Record initial balances
        uint256 initialStakerBalance = address(staker).balance;

        // Wait for some time to accumulate rewards
        vm.warp(block.timestamp + 1 days);

        // Claim rewards
        vm.prank(staker);
        uint256 rewards = vault.claimRewards();
        assertTrue(rewards > 0);

        // Verify ETH rewards
        assertEq(address(staker).balance, initialStakerBalance + rewards);
        uint256 STAKER_REWARD_PERCENTAGE = 80;
        assertEq(rewards, (swapFee * STAKER_REWARD_PERCENTAGE) / 100);
    }

    function testInsolvencyProposal() public {
        vm.startPrank(registry);
        vault.registerHook(hook);
        vault.depositUSDC(hook, 10_000 * 1e6);
        vm.stopPrank();

        // Setup stakers
        vm.prank(staker);
        vault.stakeUNI(STAKE_AMOUNT, hook);
        vm.prank(staker2);
        vault.stakeUNI(STAKE_AMOUNT, hook);

        // Create proposal
        vm.prank(registry);
        PoolId poolId = PoolId.wrap(bytes32(uint256(1)));
        uint256 proposalId = vault.proposeInsolvency(hook, poolId);

        // Cast votes
        vm.prank(staker);
        vault.castVote(proposalId);
        vm.prank(staker2);
        vault.castVote(proposalId);

        // Execute proposal
        vm.prank(registry);
        vault.executeProposal(proposalId);

        // Verify proposal execution
        (,,,, bool executed, bool passed) = vault.getProposal(proposalId);
        assertTrue(executed);
        assertTrue(passed);
    }

    function testVaultMetrics() public {
        vm.prank(registry);
        vault.registerHook(hook);

        // Test deposit
        uint256 depositAmount = 10_000 * 1e6;
        vm.prank(registry);
        vault.depositUSDC(hook, depositAmount);

        // Test staking
        vm.prank(staker);
        vault.stakeUNI(STAKE_AMOUNT, hook);

        // Verify vault info
        IInsuranceVault.VaultInfo memory vInfo = vault.getVaultInfo();
        assertEq(vInfo.totalUSDCDeposited, depositAmount);
        assertEq(vInfo.totalUNIStaked, STAKE_AMOUNT);

        // Verify stake info
        IInsuranceVault.StakeInfo memory sInfo = vault.getStakeInfo(staker);
        assertEq(sInfo.amount, STAKE_AMOUNT);
        assertEq(sInfo.lastRewardTime, block.timestamp);
    }
}
