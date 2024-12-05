// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "brevis/sdk/apps/framework/BrevisApp.sol";
import {IBrevisProof} from "brevis/sdk/interface/IBrevisProof.sol";
import {IInsuranceVault} from "./interfaces/IInsuranceVault.sol";
import "forge-std/console.sol";

contract BrevisHandler is BrevisApp, Ownable {
    bytes32 public vkHash;
    IInsuranceVault insuranceVault;

    constructor(address _brevisProof, address _insuranceVault) BrevisApp(_brevisProof) Ownable() {
        insuranceVault = IInsuranceVault(_insuranceVault);
        _transferOwnership(msg.sender);
    }

    function handleProofResult(bytes32, /*_requestId*/ bytes32 _vkHash, bytes calldata _circuitOutput) internal {
        require(vkHash == _vkHash, "invalid vk");

        (address[] memory users, address[] memory hooks, uint256[] memory amounts) = decodeOutput(_circuitOutput);
        console.logAddress(users[0]);
        console.logAddress(hooks[0]);
        console.logUint(amounts[0]);
        insuranceVault.setVictims(users, hooks, amounts);
    }

    function decodeOutput(bytes calldata o)
        internal
        pure
        returns (address[] memory, address[] memory, uint256[] memory)
    {
        // Each record is 72 bytes long
        uint256 recordLength = 72;
        uint256 numberOfRecords = o.length / recordLength;

        address[] memory users = new address[](numberOfRecords);
        address[] memory currencies = new address[](numberOfRecords);
        uint256[] memory amounts = new uint256[](numberOfRecords);

        uint256 offset = 0;

        for (uint256 i = 0; i < numberOfRecords; i++) {
            users[i] = address(bytes20(o[offset:offset + 20]));
            currencies[i] = address(bytes20(o[offset + 20:offset + 40]));
            amounts[i] = bytesToUint256(o[offset + 40:offset + 72]);
            offset += recordLength;
        }

        return (users, currencies, amounts);
    }

    function bytesToUint256(bytes memory b) internal pure returns (uint256) {
        require(b.length == 32, "Invalid bytes length for conversion");

        uint256 number;
        for (uint256 i = 0; i < 32; i++) {
            number = number | (uint256(uint8(b[i])) << (8 * (31 - i)));
        }
        return number;
    }

    function setVkHash(bytes32 _vkHash) external onlyOwner {
        vkHash = _vkHash;
    }
}
