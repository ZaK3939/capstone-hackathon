// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookRegistry} from "../src/HookRegistry.sol";
import {InsuranceVault} from "../src/InsuranceVault.sol";
import {InsuredHook} from "../src/InsuredHook.sol";
import {MockERC20} from "../test/mock/MockERC20.sol";
import {Constants} from "./base/Constants.sol";

contract InsuredHookScript is Script, Constants {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Now we can use POOLMANAGER from Constants
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        MockERC20 uni = new MockERC20("UNI", "UNI", 18);

        HookRegistry registry = new HookRegistry(address(usdc), address(this));

        InsuranceVault vault = new InsuranceVault(address(registry), address(usdc), address(uni));

        registry.setVault(address(vault));

        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144));

        bytes memory constructorArgs = abi.encode(POOLMANAGER, address(registry), address(vault));

        bytes memory creationCode = type(InsuredHook).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);

        assembly {
            flags := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(flags)) { revert(0, 0) }
        }

        require(address(InsuredHook(flags)) != address(0), "InsuredHookScript: deployment failed");

        vm.stopBroadcast();
    }
}
