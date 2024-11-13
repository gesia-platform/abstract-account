// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "../interfaces/IEntryPoint.sol";

/**
 * nonce 관리 기능을 제공하는 컨트랙트
 */
contract NonceManager is INonceManager {

    /**
     * 주어진 nonce 키에 대한 다음 유효한 시퀀스 번호.
     */
    mapping(address => mapping(uint192 => uint256)) public nonceSequenceNumber;

    /**
     * 지정된 주소와 키에 대한 현재 nonce 값을 반환합니다.
     * nonce는 64비트 시퀀스 번호와 192비트 키로 구성됩니다.
     * @param sender - nonce를 조회할 계정 주소
     * @param key - nonce에 사용될 키
     * @return nonce - 계산된 nonce 값
     */
    function getNonce(address sender, uint192 key)
        public view override returns (uint256 nonce) 
    {
        return nonceSequenceNumber[sender][key] | (uint256(key) << 64);
    }

    /**
     * 계정이 자신의 nonce를 수동으로 증가시킬 수 있게 허용하는 함수.
     * 주로 컨트랙트 생성 중에 nonce를 0이 아닌 값으로 설정하여 
     * 첫 번째 nonce 증가에 대한 가스 비용을 초기 생성 시에 흡수할 수 있게 함.
     * @param key - 증가시킬 nonce의 키
     */
    function incrementNonce(uint192 key) public override {
        nonceSequenceNumber[msg.sender][key]++;
    }

    /**
     * 이 계정에 대해 nonce가 고유한지 검증하고 업데이트하는 함수.
     * validateUserOp() 호출 직후 호출됨.
     * @param sender - nonce를 검증할 계정 주소
     * @param nonce - 검증할 nonce 값
     * @return 성공하면 true를 반환하고, 실패하면 false를 반환
     */
    function _validateAndUpdateNonce(address sender, uint256 nonce) internal returns (bool) {
        uint192 key = uint192(nonce >> 64); // 상위 192비트는 키로 사용
        uint64 seq = uint64(nonce);         // 하위 64비트는 시퀀스 번호로 사용
        return nonceSequenceNumber[sender][key]++ == seq;
    }
}
