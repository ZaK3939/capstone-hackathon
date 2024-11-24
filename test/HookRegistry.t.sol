// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HookRegistry} from "../src/HookRegistry.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {MockInsuranceVault} from "./mock/MockInsuranceVault.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHookRegistry} from "../src/interfaces/IHookRegistry.sol";
import {InsuredHook} from "../src/InsuredHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

contract HookRegistryTest is Test, Fixtures {
    HookRegistry public registry;
    MockERC20 public usdc;
    MockInsuranceVault public vault;
    InsuredHook public hook;
    PoolId public poolId;

    address public owner;
    address public operator;

    event HookRegistered(address indexed hook, address indexed developer, uint256 deposit);
    event OperatorRegistered(address indexed operator);
    event OperatorRemoved(address indexed operator);
    event HookPaused(address indexed hook, PoolId indexed poolId);

    function setUp() public {
        // Setup base contracts
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        owner = address(this);
        operator = makeAddr("operator");

        // Deploy mock contracts
        usdc = new MockERC20("USDC", "USDC", 6);
        vault = new MockInsuranceVault();
        registry = new HookRegistry(address(usdc), address(vault));

        // Setup hook
        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144));
        bytes memory constructorArgs = abi.encode(manager, address(registry), address(vault));
        deployCodeTo("InsuredHook.sol:InsuredHook", constructorArgs, flags);
        hook = InsuredHook(flags);

        // Setup pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Setup USDC
        usdc.mint(address(this), 100_000 * 1e6);
        usdc.approve(address(registry), type(uint256).max);
    }

    function testRegisterHook() public {
        uint256 depositAmount = 10_000 * 1e6;

        vm.expectEmit(true, true, false, true);
        emit HookRegistered(address(hook), address(this), depositAmount);

        registry.registerHook(address(hook), depositAmount);

        (address developer, uint256 deposit, bool isActive, uint256 riskScore) = registry.getHookInfo(address(hook));

        assertEq(developer, address(this));
        assertEq(deposit, depositAmount);
        assertTrue(isActive);
        assertEq(riskScore, 0);
    }

    function testRegisterHookInsufficientDeposit() public {
        uint256 smallDeposit = 5_000 * 1e6;

        vm.expectRevert(IHookRegistry.InvalidDeposit.selector);
        registry.registerHook(address(hook), smallDeposit);
    }

    function testOperatorManagement() public {
        // Register operator
        vm.expectEmit(true, false, false, true);
        emit OperatorRegistered(operator);
        registry.registerOperator(operator);
        assertTrue(registry.isOperatorApproved(operator));

        // Remove operator
        vm.expectEmit(true, false, false, true);
        emit OperatorRemoved(operator);
        registry.removeOperator(operator);
        assertFalse(registry.isOperatorApproved(operator));
    }

    function testPauseHook() public {
        // Register hook first
        registry.registerHook(address(hook), 10_000 * 1e6);

        // Register operator
        registry.registerOperator(operator);

        PoolId poolId = PoolId.wrap(bytes32(uint256(1)));

        // Only operator can pause
        vm.prank(operator);
        registry.pauseHook(address(hook), poolId);

        assertTrue(registry.isPoolPaused(address(hook), poolId));
    }

    function testPauseHookUnauthorized() public {
        registry.registerHook(address(hook), 10_000 * 1e6);
        PoolId poolId = PoolId.wrap(bytes32(uint256(1)));

        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(IHookRegistry.NotAuthorized.selector);
        registry.pauseHook(address(hook), poolId);
    }

    function testUpdateRiskScore() public {
        registry.registerHook(address(hook), 10_000 * 1e6);
        registry.registerOperator(operator);

        vm.prank(operator);
        registry.updateRiskScore(address(hook), 75);

        assertEq(registry.getRiskScore(address(hook)), 75);
    }
}
