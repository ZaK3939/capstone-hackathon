// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniGuardServiceManager} from "uniguard-avs/contracts/src/interfaces/IUniGuardServiceManager.sol";

contract MockServiceManager is IUniGuardServiceManager {
    uint32 private taskNum;
    mapping(uint32 => bytes32) private taskHashes;
    mapping(address => mapping(uint32 => bytes)) private taskResponses;

    function setHookRegistry(address _hookRegistry) external {}

    function latestTaskNum() external view returns (uint32) {
        return taskNum;
    }

    function allTaskHashes(uint32 taskIndex) external view returns (bytes32) {
        return taskHashes[taskIndex];
    }

    function allTaskResponses(address operator, uint32 taskIndex) external view returns (bytes memory) {
        return taskResponses[operator][taskIndex];
    }

    function createNewTask(string memory name) external returns (Task memory) {
        Task memory newTask = Task({name: name, taskCreatedBlock: uint32(block.number)});

        taskNum++;
        taskHashes[taskNum] = keccak256(abi.encode(newTask));

        emit NewTaskCreated(taskNum, newTask);

        return newTask;
    }

    function respondToTask(
        Task calldata task,
        uint32 referenceTaskIndex,
        bytes calldata signature,
        string memory metrics,
        uint256 riskScore,
        address hook
    ) external {
        taskResponses[msg.sender][referenceTaskIndex] = abi.encode(task, metrics);
        emit TaskResponded(referenceTaskIndex, task, msg.sender);
    }
}
