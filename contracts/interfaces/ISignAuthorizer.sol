// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISignAuthorizer {
    function isAuthorizedSigner(address signer) external view returns (bool);
}
