// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/**
 * EntryPoint를 위한 헬퍼 컨트랙트로, EntryPoint가 아닌 "중립" 주소에서 userOp.initCode를 호출하기 위한 기능을 제공.
 */
contract SenderCreator {

    /**
     * "initCode" 팩토리를 호출하여 사용자 계정을 생성하고, 해당 계정 주소를 반환하는 함수.
     * @param initCode UserOp의 initCode 값. 20바이트의 팩토리 주소와 calldata가 포함되어 있음.
     * @return sender 생성된 계정의 주소. 실패 시 zero address 반환.
     */
    function createSender(bytes calldata initCode) external returns (address sender) {
        address factory = address(bytes20(initCode[0 : 20])); // initCode에서 첫 20바이트를 추출해 팩토리 주소로 사용
        bytes memory initCallData = initCode[20 :];           // 나머지 부분은 initCallData로 사용
        bool success;

        /* solhint-disable no-inline-assembly */
        assembly {
            // 팩토리 주소를 호출하여 계정을 생성하고, 성공 시 생성된 주소를 mload(0)로 로드
            success := call(gas(), factory, 0, add(initCallData, 0x20), mload(initCallData), 0, 32)
            sender := mload(0)
        }
        
        // 호출이 실패하면 sender를 zero address로 설정
        if (!success) {
            sender = address(0);
        }
    }
}
