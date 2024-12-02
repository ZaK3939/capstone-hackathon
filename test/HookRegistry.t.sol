// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HookRegistry} from "../src/HookRegistry.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {InsuranceVault} from "../src/InsuranceVault.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHookRegistry} from "../src/interfaces/IHookRegistry.sol";
import {InsuredHook} from "../src/InsuredHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {MockServiceManager} from "./mock/MockServiceManager.sol";

contract HookRegistryTest is Test, Fixtures {
    HookRegistry public registry;
    MockERC20 public usdc;
    MockERC20 public uni;
    InsuranceVault public vault;
    InsuredHook public hook;
    PoolId public poolId;
    MockServiceManager public mockServiceManager;

    address public owner;

    event HookRegistered(address indexed hook, address indexed developer, uint256 deposit);
    event HookActivated(address indexed hook);
    event HookDeactivated(address indexed hook);
    event HookPaused(address indexed hook);
    event HookUnpaused(address indexed hook);
    event RiskScoreUpdated(address indexed hook, uint256 score);
    event ServiceManagerSet(address indexed serviceManager);

    function setUp() public {
        // Setup base contracts
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        owner = address(this);

        // Deploy tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        uni = new MockERC20("UNI", "UNI", 18);

        // Deploy registry first with temporary vault
        registry = new HookRegistry(address(usdc), address(1));

        // Deploy mock service manager and set it
        mockServiceManager = new MockServiceManager();
        registry.setServiceManager(address(mockServiceManager));

        // Deploy real vault
        vault = new InsuranceVault(address(registry), address(usdc), address(uni));

        // Link registry to vault
        registry.setVault(address(vault));

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
        usdc.approve(address(vault), type(uint256).max);

        // Setup UNI
        uni.mint(address(this), 100_000 * 1e18);
        uni.approve(address(vault), type(uint256).max);
    }

    function testRegisterHook() public {
        uint256 depositAmount = 10_000 * 1e6;

        // Register hook
        vm.expectEmit(true, true, false, true);
        emit HookRegistered(address(hook), address(this), depositAmount);
        registry.registerHook(address(hook), depositAmount);

        (address developer, uint256 deposit, bool isActive, bool isPaused, uint256 riskScore) =
            registry.getHookInfo(address(hook));

        assertEq(developer, address(this));
        assertEq(deposit, depositAmount);
        assertFalse(isActive);
        assertFalse(isPaused);
        assertEq(riskScore, 0);

        // Verify vault registration
        assertTrue(vault.registeredHooks(address(hook)));
    }

    function testSetServiceManager() public {
        // Deploy new registry for this test
        HookRegistry newRegistry = new HookRegistry(address(usdc), address(1));
        address newServiceManager = makeAddr("newServiceManager");

        // Initial state check
        assertFalse(newRegistry.isServiceManagerSet());

        // Test setting service manager
        vm.expectEmit(true, false, false, false);
        emit ServiceManagerSet(newServiceManager);
        newRegistry.setServiceManager(newServiceManager);

        // Verify service manager is set
        assertTrue(newRegistry.isServiceManagerSet());
        assertEq(address(newRegistry.serviceManager()), newServiceManager);
    }

    function testPauseHook() public {
        // Register hook first
        registry.registerHook(address(hook), 10_000 * 1e6);

        // Pause hook using mock service manager
        vm.prank(address(mockServiceManager));
        vm.expectEmit(true, false, false, true);
        emit HookPaused(address(hook));
        registry.pauseHook(address(hook));

        assertTrue(registry.isHookPaused(address(hook)));
    }

    function testUpdateRiskScore() public {
        // Register hook first
        registry.registerHook(address(hook), 10_000 * 1e6);

        // Update risk score using mock service manager
        vm.prank(address(mockServiceManager));
        vm.expectEmit(true, false, false, true);
        emit RiskScoreUpdated(address(hook), 75);
        registry.updateRiskScore(address(hook), 75);

        assertEq(registry.getRiskScore(address(hook)), 75);
    }

    function testPauseUnregisteredHook() public {
        vm.prank(address(mockServiceManager));
        vm.expectRevert(IHookRegistry.HookNotRegistered.selector);
        registry.pauseHook(address(hook));
    }

    function testUpdateRiskScoreUnregisteredHook() public {
        vm.prank(address(mockServiceManager));
        vm.expectRevert(IHookRegistry.HookNotRegistered.selector);
        registry.updateRiskScore(address(hook), 75);
    }

    function testUnauthorizedServiceManagerSet() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.setServiceManager(address(mockServiceManager));
    }

    function testSetServiceManagerTwice() public {
        address newServiceManager = makeAddr("newServiceManager");
        vm.expectRevert("ServiceManager already set");
        registry.setServiceManager(newServiceManager);
    }
}
