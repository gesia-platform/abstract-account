// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-empty-blocks */

import "../interfaces/IAccount.sol";
import "../interfaces/IEntryPoint.sol";
import "./Helpers.sol";

/**
 * 기본 계정 구현.
 * 이 컨트랙트는 IAccount 인터페이스를 구현하기 위한 기본 로직을 제공합니다 - validateUserOp
 * 특정 계정 구현은 이를 상속하여 계정별 로직을 추가해야 합니다.
 */
abstract contract BaseAccount is IAccount {
    using UserOperationLib for UserOperation;

    // 서명 실패 시 반환되는 값으로, 시간 범위는 포함되지 않습니다.
    // _packValidationData(true,0,0)에 해당합니다.
    uint256 constant internal SIG_VALIDATION_FAILED = 1;

    /**
     * 계정의 nonce(일련번호)를 반환합니다.
     * 이 메서드는 다음 순차적 nonce를 반환합니다.
     * 특정 키의 nonce는 `entrypoint.getNonce(account, key)`를 사용하여 가져올 수 있습니다.
     */
    function getNonce() public view virtual returns (uint256) {
        return entryPoint().getNonce(address(this), 0);
    }

    /**
     * 이 계정이 사용하는 entryPoint를 반환합니다.
     * 서브 클래스는 이 계정이 사용하는 현재 entryPoint를 반환해야 합니다.
     */
    function entryPoint() public view virtual returns (IEntryPoint);

    /**
     * 사용자의 서명과 nonce를 검증합니다.
     * 서브 클래스는 이 메서드를 오버라이드할 필요가 없습니다. 대신 특정 내부 검증 메서드를 오버라이드해야 합니다.
     */
    function validateUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
    external override virtual returns (uint256 validationData) {
        _requireFromEntryPoint();
        validationData = _validateSignature(userOp, userOpHash);
        _validateNonce(userOp.nonce);
        _payPrefund(missingAccountFunds);
    }

    /**
     * 요청이 알려진 entryPoint로부터 오는지 확인합니다.
     */
    function _requireFromEntryPoint() internal virtual view {
        require(msg.sender == address(entryPoint()), "account: not from EntryPoint");
    }

    /**
     * 이 메시지에 대해 서명이 유효한지 검증합니다.
     * @param userOp userOp.signature 필드를 검증합니다.
     * @param userOpHash 요청의 해시로, 서명을 확인하는 데 사용됩니다.
     *        (또한 entrypoint와 체인 ID도 해싱됩니다.)
     * @return validationData 이 작업의 서명 및 시간 범위
     *      <20-byte> sigAuthorizer - 유효한 서명의 경우 0, 서명 실패를 표시하는 경우 1,
     *         그 외에는 "authorizer" 컨트랙트의 주소입니다.
     *      <6-byte> validUntil - 이 작업이 유효한 마지막 타임스탬프. "무기한"인 경우 0.
     *      <6-byte> validAfter - 이 작업이 유효한 첫 번째 타임스탬프
     *      계정이 시간 범위를 사용하지 않는 경우 서명 실패 시 SIG_VALIDATION_FAILED 값(1)을 반환하면 충분합니다.
     *      검증 코드에서는 block.timestamp(또는 block.number)를 직접 사용할 수 없습니다.
     */
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
    internal virtual returns (uint256 validationData);

    /**
     * UserOperation의 nonce를 검증합니다.
     * 이 메서드는 이 계정의 nonce 요구 사항을 검증할 수 있습니다.
     * 예:
     * 순차적인 UserOps만 사용할 수 있도록 nonce를 제한하려면:
     *      `require(nonce < type(uint64).max)`
     * nonce가 순차적이지 않도록 제한하는 가상의 계정이 필요한 경우:
     *      `require(nonce & type(uint64).max == 0)`
     *
     * 실제 nonce의 고유성은 EntryPoint에 의해 관리되므로, 계정 자체에서는 추가 조치가 필요하지 않습니다.
     *
     * @param nonce 검증할 nonce
     *
     * solhint-disable-next-line no-empty-blocks
     */
    function _validateNonce(uint256 nonce) internal view virtual {
    }

    /**
     * 이 거래를 위한 부족한 자금을 entryPoint(msg.sender)에 송금합니다.
     * 서브 클래스는 더 나은 자금 관리를 위해 이 메서드를 오버라이드할 수 있습니다.
     * (예: future transactions에서 자금을 재송금하지 않도록 entryPoint에 최소 요구 금액보다 더 많은 자금을 송금할 수 있음)
     * @param missingAccountFunds 이 메서드가 entryPoint에 송금해야 하는 최소 금액입니다.
     *  충분한 예치금이 있거나 userOp에 paymaster가 있는 경우 이 값은 0일 수 있습니다.
     */
    function _payPrefund(uint256 missingAccountFunds) internal virtual {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{value : missingAccountFunds, gas : type(uint256).max}("");
            (success);
            // 실패는 무시합니다 (검증은 EntryPoint의 책임입니다, 계정의 책임이 아님)
        }
    }
}
