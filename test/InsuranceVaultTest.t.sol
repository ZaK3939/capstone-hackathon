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

    uint256 constant INITIAL_USDC = 100_000 * 1e6; // 100,000 USDC
    uint256 constant INITIAL_UNI = 100_000 * 1e18; // 100,000 UNI
    uint256 constant STAKE_AMOUNT = 1000 * 1e18; // 1,000 UNI

    event HookRegistered(address indexed hook);
    event USDCDeposited(address indexed hook, uint256 amount);
    event UNIStaked(address indexed staker, uint256 amount);
    event CompensationProcessed(address indexed hook, PoolId indexed poolId, uint256 usdcPaid, uint256 uniPaid);

    function setUp() public {
        // Deploy tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        uni = new MockERC20("UNI", "UNI", 18);

        // Setup accounts
        registry = makeAddr("registry");
        hook = makeAddr("hook");
        staker = makeAddr("staker");

        // Deploy vault
        vault = new InsuranceVault(registry, address(usdc), address(uni));

        // Setup initial balances
        usdc.mint(address(registry), INITIAL_USDC);
        usdc.mint(address(vault), INITIAL_USDC); // Mint additional USDC to vault for compensation
        uni.mint(address(staker), INITIAL_UNI);
        uni.mint(address(vault), INITIAL_UNI); // Mint additional UNI to vault

        // Approve vault for transactions
        vm.prank(registry);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(staker);
        uni.approve(address(vault), type(uint256).max);
    }

    function testRegisterHook() public {
        vm.prank(registry);
        vm.expectEmit(true, false, false, true);
        emit HookRegistered(hook);
        vault.registerHook(hook);

        assertTrue(vault.registeredHooks(hook));
    }

    function testRegisterHookUnauthorized() public {
        vm.expectRevert("Only registry");
        vault.registerHook(hook);
    }

    function testRegisterHookTwice() public {
        vm.startPrank(registry);
        vault.registerHook(hook);

        vm.expectRevert("Hook already registered");
        vault.registerHook(hook);
        vm.stopPrank();
    }

    function testDepositUSDC() public {
        uint256 depositAmount = 10_000 * 1e6;

        // Register hook first
        vm.prank(registry);
        vault.registerHook(hook);

        // Deposit USDC
        vm.prank(registry);
        vm.expectEmit(true, false, false, true);
        emit USDCDeposited(hook, depositAmount);
        vault.depositUSDC(hook, depositAmount);

        assertEq(vault.usdcBalances(hook), depositAmount);
        assertEq(vault.morphoBalance(), depositAmount);

        IInsuranceVault.VaultInfo memory info = vault.getVaultInfo();
        assertEq(info.totalUSDCDeposited, depositAmount);
    }

    function testStakeUNI() public {
        // Register hook first
        vm.prank(registry);
        vault.registerHook(hook);

        // Record starting balances
        uint256 stakerStartBalance = uni.balanceOf(staker);
        uint256 vaultStartBalance = uni.balanceOf(address(vault));

        // Stake UNI
        vm.recordLogs();
        vm.prank(staker);
        vault.stakeUNI(STAKE_AMOUNT, hook);

        // Verify the event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2); // Transfer + UNIStaked events
        assertEq(entries[1].topics[0], keccak256("UNIStaked(address,uint256)"));
        assertEq(entries[1].topics[1], bytes32(uint256(uint160(staker))));
        assertEq(abi.decode(entries[1].data, (uint256)), STAKE_AMOUNT);

        // Verify balances
        assertEq(uni.balanceOf(staker), stakerStartBalance - STAKE_AMOUNT);
        assertEq(uni.balanceOf(address(vault)), vaultStartBalance + STAKE_AMOUNT);
        assertEq(vault.uniBalances(staker), STAKE_AMOUNT);
        assertEq(vault.getHookStake(hook, staker), STAKE_AMOUNT);

        // Verify stake info
        IInsuranceVault.StakeInfo memory info = vault.getStakeInfo(staker);
        assertEq(info.amount, STAKE_AMOUNT);
        assertEq(info.lastRewardTime, block.timestamp);

        // Verify vault info
        IInsuranceVault.VaultInfo memory vInfo = vault.getVaultInfo();
        assertEq(vInfo.totalUNIStaked, STAKE_AMOUNT);
    }

    function testProcessCompensation() public {
        uint256 depositAmount = 10_000 * 1e6;
        uint256 lossAmount = 5_000 * 1e6;

        // Register and deposit
        vm.startPrank(registry);
        vault.registerHook(hook);
        vault.depositUSDC(hook, depositAmount);

        // Process compensation
        PoolId poolId = PoolId.wrap(bytes32(uint256(1)));
        vm.expectEmit(true, true, false, true);
        emit CompensationProcessed(hook, poolId, lossAmount, 0);
        (uint256 usdcPaid, uint256 uniPaid) = vault.processCompensation(hook, poolId, lossAmount);

        assertEq(usdcPaid, lossAmount);
        assertEq(uniPaid, 0);
        assertEq(vault.usdcBalances(hook), depositAmount - lossAmount);
        vm.stopPrank();
    }

    function testProcessCompensationWithUNILayer() public {
        uint256 depositAmount = 5_000 * 1e6;
        uint256 lossAmount = 10_000 * 1e6;

        // Setup: Register hook, deposit USDC, and stake UNI
        vm.startPrank(registry);
        vault.registerHook(hook);
        vault.depositUSDC(hook, depositAmount);
        vm.stopPrank();

        vm.prank(staker);
        vault.stakeUNI(STAKE_AMOUNT, hook);

        // Record starting balances
        uint256 startUSDCBalance = usdc.balanceOf(address(registry));
        uint256 startUNIBalance = uni.balanceOf(address(vault));

        // Process compensation
        vm.prank(registry);
        PoolId poolId = PoolId.wrap(bytes32(uint256(1)));
        (uint256 usdcPaid, uint256 uniPaid) = vault.processCompensation(hook, poolId, lossAmount);

        // Verify compensation
        assertEq(usdcPaid, depositAmount);
        assertEq(uniPaid, lossAmount - depositAmount);
        assertEq(vault.usdcBalances(hook), 0);
        assertEq(usdc.balanceOf(address(registry)), startUSDCBalance + depositAmount);
        assertTrue(uni.balanceOf(address(vault)) >= startUNIBalance - uniPaid);
    }
}
