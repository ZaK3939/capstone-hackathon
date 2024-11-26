// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {InsuranceVault} from "../src/InsuranceVault.sol";
import {HookRegistry} from "../src/HookRegistry.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

contract InsuranceVaultTest is Test {
    InsuranceVault public vault;
    HookRegistry public registry;
    MockERC20 public usdc;
    MockERC20 public uni;

    address public owner;
    address public hook;
    address public staker1;
    address public staker2;

    event USDCDeposited(address indexed hook, uint256 amount);
    event UNIStaked(address indexed user, uint256 amount);
    event RewardsDistributed(address indexed user, uint256 amount);
    event CompensationProcessed(address indexed hook, PoolId indexed poolId, uint256 usdcAmount, uint256 uniAmount);
    event HookRegistered(address indexed hook);

    function setUp() public {
        owner = address(this);
        hook = makeAddr("hook");
        staker1 = makeAddr("staker1");
        staker2 = makeAddr("staker2");

        // Deploy tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        uni = new MockERC20("UNI", "UNI", 18);

        // Deploy registry first with temporary vault
        registry = new HookRegistry(address(usdc), address(1));

        // Deploy real vault
        vault = new InsuranceVault(address(registry), address(usdc), address(uni));

        // Link registry to vault
        registry.setVault(address(vault));

        // Setup initial balances
        usdc.mint(address(this), 100_000 * 1e6);
        uni.mint(staker1, 1000 * 1e18);
        uni.mint(staker2, 1000 * 1e18);

        // Approvals
        usdc.approve(address(registry), type(uint256).max);
        vm.prank(staker1);
        uni.approve(address(vault), type(uint256).max);
        vm.prank(staker2);
        uni.approve(address(vault), type(uint256).max);
    }

    function testRegisterHook() public {
        registry.registerHook(hook, 10_000 * 1e6);
        assertTrue(vault.registeredHooks(hook));
    }

    function testDepositUSDC() public {
        uint256 depositAmount = 10_000 * 1e6;

        // Register hook and deposit USDC through registry
        registry.registerHook(hook, depositAmount);

        assertEq(vault.usdcBalances(hook), depositAmount);
        assertEq(vault.getVaultInfo().totalUSDCDeposited, depositAmount);
    }

    function testStakeUNI() public {
        // Register hook through registry
        registry.registerHook(hook, 10_000 * 1e6);

        uint256 stakeAmount = 100 * 1e18;
        vm.prank(staker1);
        vault.stakeUNI(stakeAmount, hook);

        assertEq(vault.uniBalances(staker1), stakeAmount);
        assertEq(vault.getHookStake(hook, staker1), stakeAmount);
        assertEq(vault.getVaultInfo().totalUNIStaked, stakeAmount);
    }

    function testProcessCompensation() public {
        // Register hook and deposit USDC
        uint256 depositAmount = 10_000 * 1e6;
        registry.registerHook(hook, depositAmount);

        // Stake UNI
        uint256 stakeAmount = 100 * 1e18;
        vm.prank(staker1);
        vault.stakeUNI(stakeAmount, hook);

        // Process compensation
        uint256 lossAmount = 5_000 * 1e6;
        PoolId poolId = PoolId.wrap(bytes32(uint256(1)));

        vm.prank(address(registry));
        (uint256 usdcPaid, uint256 uniPaid) = vault.processCompensation(hook, poolId, lossAmount);

        assertEq(usdcPaid, lossAmount);
        assertEq(uniPaid, 0);
        assertEq(vault.usdcBalances(hook), depositAmount - lossAmount);
    }

    // Add more test cases...
}
