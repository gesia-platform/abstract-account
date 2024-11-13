// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

interface IOracle {

    /**
     * 주어진 양의 이더리움을 받기 위해 필요한 토큰의 양을 반환합니다.
     */
    function getTokenValueOfEth(uint256 ethOutput) external view returns (uint256 tokenInput);
}
