// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "brevis/sdk/interface/IBrevisTypes.sol";
import "brevis/sdk/lib/Lib.sol";
import "brevis/interfaces/ISigsVerifier.sol";
import "brevis/sdk/interface/IBrevisRequest.sol";

contract MockBrevisRequest is IBrevisRequest {
    mapping(bytes32 => mapping(uint64 => RequestStatus)) private requests;
    mapping(bytes32 => mapping(uint64 => uint8)) private options;
    string private baseDataUrl = "https://example.com/";
    uint256 public requestTimeout = 1 days;

    function sendRequest(bytes32 _proofId, uint64 _nonce, address _refundee, Callback calldata _callback, uint8 _option)
        external
        payable
        override
    {
        requests[_proofId][_nonce] = RequestStatus.ZkPending;
        options[_proofId][_nonce] = _option;
        emit RequestSent(_proofId, _nonce, _refundee, msg.value, _callback, _option);
    }

    function fulfillRequest(
        bytes32 _proofId,
        uint64 _nonce,
        uint64 _chainId,
        bytes calldata _proof,
        bytes calldata _appCircuitOutput,
        address _callbackTarget
    ) external override {
        requests[_proofId][_nonce] = RequestStatus.ZkAttested;
        emit RequestFulfilled(_proofId, _nonce);
    }

    function fulfillRequests(
        bytes32[] calldata _proofIds,
        uint64[] calldata _nonces,
        uint64 _chainId,
        bytes calldata _proof,
        Brevis.ProofData[] calldata _proofDataArray,
        bytes[] calldata _appCircuitOutputs,
        address[] calldata _callbackTargets
    ) external override {
        for (uint256 i = 0; i < _proofIds.length; i++) {
            requests[_proofIds[i]][_nonces[i]] = RequestStatus.ZkAttested;
        }
        emit RequestsFulfilled(_proofIds, _nonces);
    }

    function fulfillOpRequests(
        bytes32[] calldata _proofIds,
        uint64[] calldata _nonces,
        bytes32[] calldata _appCommitHashes,
        bytes32[] calldata _appVkHashes,
        IBvnSigsVerifier.SigInfo calldata _bvnSigInfo,
        IAvsSigsVerifier.SigInfo calldata _eigenSigInfo
    ) external override {
        for (uint256 i = 0; i < _proofIds.length; i++) {
            requests[_proofIds[i]][_nonces[i]] = RequestStatus.ZkAttested;
        }
        emit OpRequestsFulfilled(_proofIds, _nonces, _appCommitHashes, _appVkHashes);
    }

    function refund(bytes32 _proofId, uint64 _nonce, uint256 _amount, address _refundee) external override {
        requests[_proofId][_nonce] = RequestStatus.Refunded;
        emit RequestRefunded(_proofId, _nonce);
    }

    function increaseGasFee(bytes32 _proofId, uint64 _nonce, uint64 _addGas, uint256 _currentFee, address _refundee)
        external
        payable
        override
    {
        emit RequestFeeIncreased(_proofId, _nonce, _addGas, msg.value);
    }

    function queryRequestStatus(bytes32 _proofId, uint64 _nonce)
        external
        view
        override
        returns (RequestStatus, uint8)
    {
        return (requests[_proofId][_nonce], options[_proofId][_nonce]);
    }

    function queryRequestStatus(bytes32 _proofId, uint64 _nonce, uint256 _appChallengeWindow)
        external
        view
        override
        returns (RequestStatus, uint8)
    {
        return (requests[_proofId][_nonce], options[_proofId][_nonce]);
    }

    function validateOpAppData(
        bytes32 _proofId,
        uint64 _nonce,
        bytes32 _appCommitHash,
        bytes32 _appVkHash,
        uint8 _option
    ) external view override returns (bool) {
        return true;
    }

    function validateOpAppData(
        bytes32 _proofId,
        uint64 _nonce,
        bytes32 _appCommitHash,
        bytes32 _appVkHash,
        uint256 _appChallengeWindow,
        uint8 _option
    ) external view override returns (bool) {
        return true;
    }

    function validateOpAppData(
        bytes32[] calldata _proofIds,
        uint64[] calldata _nonces,
        bytes32[] calldata _appCommitHashes,
        bytes32[] calldata _appVkHashes,
        uint256 _appChallengeWindow,
        uint8 _option
    ) external view override returns (bool) {
        return true;
    }

    function dataURL(bytes32 _proofId) external view override returns (string memory) {
        return string(abi.encodePacked(baseDataUrl, _proofId));
    }

    // Helper functions for testing
    function setRequestStatus(bytes32 _proofId, uint64 _nonce, RequestStatus _status) external {
        requests[_proofId][_nonce] = _status;
    }

    function setBaseDataUrl(string memory _newUrl) external {
        string memory oldUrl = baseDataUrl;
        baseDataUrl = _newUrl;
        emit BaseDataUrlUpdated(oldUrl, _newUrl);
    }

    function setRequestTimeout(uint256 _newTimeout) external {
        uint256 oldTimeout = requestTimeout;
        requestTimeout = _newTimeout;
        emit RequestTimeoutUpdated(oldTimeout, _newTimeout);
    }
}
