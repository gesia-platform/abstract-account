// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./SimpleAccount.sol";

/**
 * SimpleAccount를 위한 샘플 팩토리 계약
 * UserOperations의 "initCode"는 팩토리 주소와 (이 샘플 팩토리에서) createAccount 호출 메서드를 포함합니다.
 * 팩토리의 createAccount는 계정이 이미 배포되어 있어도 대상 계정 주소를 반환합니다.
 * 이렇게 하면, entryPoint.getSenderAddress()는 계정이 생성되기 전후에 호출할 수 있습니다.
 */
contract SimpleAccountFactory {
    SimpleAccount public immutable accountImplementation;
    address public operatorManager;

    constructor(IEntryPoint _entryPoint, address _operatorManager) {
        accountImplementation = new SimpleAccount(_entryPoint, _operatorManager);
        operatorManager = _operatorManager;
    }

    /**
     * 계정을 생성하고 그 주소를 반환합니다.
     * 계정이 이미 배포되어 있어도 주소를 반환합니다.
     * UserOperation 실행 중에, 이 메서드는 계정이 배포되지 않은 경우에만 호출됩니다.
     * 이 메서드는 기존 계정 주소를 반환하여 entryPoint.getSenderAddress()가 계정 생성 후에도 작동하도록 합니다.
     */
    function createAccount(address owner, uint256 salt) public returns (SimpleAccount ret) {
        address addr = getAddress(owner, salt);
        uint codeSize = addr.code.length;
        if (codeSize > 0) {
            return SimpleAccount(payable(addr));
        }
        ret = SimpleAccount(payable(new ERC1967Proxy{salt : bytes32(salt)}(
                address(accountImplementation),
                abi.encodeCall(SimpleAccount.initialize, (owner, operatorManager))
            )));
    }

    /**
     * 이 계정의 카운터팩추얼 주소를 계산하여 createAccount()에서 반환되는 주소를 구합니다.
     */
    function getAddress(address owner, uint256 salt) public view returns (address) {
        return Create2.computeAddress(bytes32(salt), keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    address(accountImplementation),
                    abi.encodeCall(SimpleAccount.initialize, (owner, operatorManager))
                )
            )));
    }
}
