// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {InsuredHook} from "../src/InsuredHook.sol";
import {HookRegistry} from "../src/HookRegistry.sol";
import {InsuranceVault} from "../src/InsuranceVault.sol";
import {IInsuredHook} from "../src/interfaces/IInsuredHook.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {UniGuardServiceManager} from "uniguard-avs/contracts/src/UniGuardServiceManager.sol";
import {IUniGuardServiceManager} from "uniguard-avs/contracts/src/interfaces/IUniGuardServiceManager.sol";
import {HelloWorldDeploymentLib} from "uniguard-avs/contracts/script/utils/HelloWorldDeploymentLib.sol";
import {CoreDeploymentLib} from "uniguard-avs/contracts/script/utils/CoreDeploymentLib.sol";
import {UpgradeableProxyLib} from "uniguard-avs/contracts/script/utils/UpgradeableProxyLib.sol";
import {
    Quorum,
    StrategyParams,
    IStrategy
} from "@eigenlayer-middleware/src/interfaces/IECDSAStakeRegistryEventsAndErrors.sol";
import {ERC20Mock} from "./mock/ERC20Mock.sol";
import {IERC20, StrategyFactory} from "@eigenlayer/contracts/strategies/StrategyFactory.sol";
// import {ECDSAStakeRegistry} from "uniguard-avs/contracts/lib/eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";

contract InsuredHookIntegrationTest is Test, Fixtures {
    InsuredHook hook;
    HookRegistry registry;
    InsuranceVault vault;
    UniGuardServiceManager serviceManager;
    MockERC20 usdc;
    MockERC20 uni;
    PoolId poolId;
    HelloWorldDeploymentLib.DeploymentData internal helloWorldDeployment;
    CoreDeploymentLib.DeploymentData internal coreDeployment;
    CoreDeploymentLib.DeploymentConfigData coreConfigData;
    Quorum quorum;
    ERC20Mock public mockToken;

    // Test constants
    uint256 constant INITIAL_DEPOSIT = 10000e6; // 10,000 USDC
    uint256 constant THRESHOLD_AMOUNT = 5000e6; // 5,000 USDC for testing
    mapping(address => IStrategy) public tokenToStrategy;

    function setUp() public {
        // Deploy v4-core contracts and setup currencies
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        // Deploy mock tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        uni = new MockERC20("UNI", "UNI", 18);

        // Deploy core contracts with proxy admin
        address proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();

        // Deploy core contracts configuration
        coreConfigData = CoreDeploymentLib.readDeploymentConfigValues("test/mockData/config/core/", 1337); // TODO: Fix this to correct path
        coreDeployment = CoreDeploymentLib.deployContracts(proxyAdmin, coreConfigData);

        // Setup registry and vault
        registry = new HookRegistry(address(usdc), address(this));
        vault = new InsuranceVault(address(registry), address(usdc), address(uni));
        registry.setVault(address(vault));

        // Deploy service manager through deployment lib
        mockToken = new ERC20Mock();

        IStrategy strategy = addStrategy(address(mockToken));
        quorum.strategies.push(StrategyParams({strategy: strategy, multiplier: 10_000}));
        helloWorldDeployment = HelloWorldDeploymentLib.deployContracts(proxyAdmin, coreDeployment, quorum);
        serviceManager = UniGuardServiceManager(helloWorldDeployment.helloWorldServiceManager);

        // Configure registry
        registry.setServiceManager(address(serviceManager));

        // Setup hook with proper flags
        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144));
        bytes memory constructorArgs = abi.encode(manager, address(registry), address(vault));
        deployCodeTo("InsuredHook.sol:InsuredHook", constructorArgs, flags);
        hook = InsuredHook(flags);

        // Initialize pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Mint initial tokens
        usdc.mint(address(this), INITIAL_DEPOSIT);
        uni.mint(address(this), 1000e18);
    }

    function addStrategy(address token) public returns (IStrategy) {
        if (tokenToStrategy[token] != IStrategy(address(0))) {
            return tokenToStrategy[token];
        }

        StrategyFactory strategyFactory = StrategyFactory(coreDeployment.strategyFactory);
        IStrategy newStrategy = strategyFactory.deployNewStrategy(IERC20(token));
        tokenToStrategy[token] = newStrategy;
        return newStrategy;
    }

    function testHookRegistration() public {
        // Step 1: Register hook
        usdc.approve(address(registry), INITIAL_DEPOSIT);
        registry.registerHook(address(hook), INITIAL_DEPOSIT);

        // Verify registration
        (address developer, uint256 deposit, bool active,, uint256 riskScore) = registry.getHookInfo(address(hook));
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
        (,,,, uint256 newRiskScore) = registry.getHookInfo(address(hook));
        assertEq(newRiskScore, 80);
    }

    // function testHookPause() public {
    //     // Setup
    //     testHookRegistration();
    //     testAnomalyDetection();

    //     // Pause hook via registry
    //     bytes32 poolId = bytes32(uint256(1)); // Example pool ID
    //     vm.prank(address(registry));
    //     hook.pause(poolId);

    //     // Verify pause status
    //     assertTrue(hook.isPaused(poolId));
    // }

    // function testInsolvencyDetermination() public {
    //     // Setup
    //     testHookRegistration();
    //     testAnomalyDetection();
    //     testHookPause();

    //     // Simulate loss event
    //     uint256 lossAmount = THRESHOLD_AMOUNT;
    //     bytes32 poolId = bytes32(uint256(1));

    //     // Process compensation
    //     vm.prank(address(registry));
    //     (uint256 usdcPaid, uint256 uniPaid) = vault.processCompensation(address(hook), poolId, lossAmount);

    //     // Verify compensation
    //     assertEq(usdcPaid + uniPaid, lossAmount);
    // }

    // function testInsolvencyResolution() public {
    //     // Setup
    //     testHookRegistration();
    //     testAnomalyDetection();
    //     testHookPause();
    //     testInsolvencyDetermination();

    //     bytes32 poolId = bytes32(uint256(1));

    //     // Verify hook status after insolvency
    //     (,, bool active,) = registry.getHookInfo(address(hook));
    //     assertFalse(active);

    //     // Verify pool remains paused
    //     assertTrue(hook.isPaused(poolId));
    // }
}
