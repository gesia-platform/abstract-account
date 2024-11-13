// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable no-inline-assembly */

/**
 * validateUserOp에서 반환되는 데이터 구조체.
 * validateUserOp은 uint256 값을 반환하며, `_packedValidationData`로 생성되고 `_parseValidationData`로 해석됨.
 * @param aggregator - address(0): 계정이 스스로 서명을 검증했음을 의미.
 *                     address(1): 계정이 서명 검증에 실패했음을 의미.
 *                     그 외의 경우, 서명 검증에 사용해야 하는 서명 집계자 주소.
 * @param validAfter - 이 UserOp가 유효해지는 시작 타임스탬프.
 * @param validUntil - 이 UserOp가 유효한 종료 타임스탬프.
 */
struct ValidationData {
    address aggregator;
    uint48 validAfter;
    uint48 validUntil;
}

// sigFailed, validAfter, validUntil 추출.
// 또한 유효한 종료가 0일 경우 type(uint48).max로 변환.
function _parseValidationData(uint validationData) pure returns (ValidationData memory data) {
    address aggregator = address(uint160(validationData));
    uint48 validUntil = uint48(validationData >> 160);
    if (validUntil == 0) {
        validUntil = type(uint48).max;
    }
    uint48 validAfter = uint48(validationData >> (48 + 160));
    return ValidationData(aggregator, validAfter, validUntil);
}

// account와 paymaster의 유효 시간 범위 교차.
function _intersectTimeRange(uint256 validationData, uint256 paymasterValidationData) pure returns (ValidationData memory) {
    ValidationData memory accountValidationData = _parseValidationData(validationData);
    ValidationData memory pmValidationData = _parseValidationData(paymasterValidationData);
    address aggregator = accountValidationData.aggregator;
    if (aggregator == address(0)) {
        aggregator = pmValidationData.aggregator;
    }
    uint48 validAfter = accountValidationData.validAfter;
    uint48 validUntil = accountValidationData.validUntil;
    uint48 pmValidAfter = pmValidationData.validAfter;
    uint48 pmValidUntil = pmValidationData.validUntil;

    if (validAfter < pmValidAfter) validAfter = pmValidAfter;
    if (validUntil > pmValidUntil) validUntil = pmValidUntil;
    return ValidationData(aggregator, validAfter, validUntil);
}

/**
 * validateUserOp의 반환 값을 압축하는 도우미 함수.
 * @param data - 압축할 ValidationData 구조체
 */
function _packValidationData(ValidationData memory data) pure returns (uint256) {
    return uint160(data.aggregator) | (uint256(data.validUntil) << 160) | (uint256(data.validAfter) << (160 + 48));
}

/**
 * 서명 집계자를 사용하지 않을 경우 validateUserOp의 반환 값을 압축하는 도우미 함수.
 * @param sigFailed - 서명 실패 여부 (true: 실패, false: 성공)
 * @param validUntil - UserOperation이 유효한 마지막 타임스탬프 (무제한의 경우 0)
 * @param validAfter - UserOperation이 유효해지는 첫 타임스탬프
 */
function _packValidationData(bool sigFailed, uint48 validUntil, uint48 validAfter) pure returns (uint256) {
    return (sigFailed ? 1 : 0) | (uint256(validUntil) << 160) | (uint256(validAfter) << (160 + 48));
}

/**
 * calldata에 대해 keccak 해시 계산 함수.
 * @dev calldata를 메모리에 복사한 후 keccak 계산을 수행하고, 할당된 메모리를 삭제함.
 *      이상하게도 솔리디티로 직접 해시를 계산하는 것보다 더 효율적임.
 */
function calldataKeccak(bytes calldata data) pure returns (bytes32 ret) {
    assembly {
        let mem := mload(0x40)
        let len := data.length
        calldatacopy(mem, data.offset, len)
        ret := keccak256(mem, len)
    }
}
