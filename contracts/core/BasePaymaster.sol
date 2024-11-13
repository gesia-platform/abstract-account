// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;


/* solhint-disable reason-string */

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPaymaster.sol";
import "../interfaces/IEntryPoint.sol";
import "./Helpers.sol";

/**
 * 페이마스터 생성을 위한 도우미 클래스.
 * 스테이킹을 위한 도우미 메서드를 제공.
 * postOp 함수가 entryPoint에서만 호출되는지 검증.
 */
abstract contract BasePaymaster is IPaymaster, Ownable {

    IEntryPoint immutable public entryPoint;

    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
    }

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
    external override returns (bytes memory context, uint256 validationData) {
         _requireFromEntryPoint();
        return _validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
    internal virtual returns (bytes memory context, uint256 validationData);

    /// @inheritdoc IPaymaster
    function postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) external override {
        _requireFromEntryPoint();
        _postOp(mode, context, actualGasCost);
    }

    /**
     * 후처리 작업 핸들러.
     * (entryPoint를 통해서만 호출되는지 확인됨)
     * @dev validatePaymasterUserOp이 비어 있지 않은 context를 반환하면, 이 메서드를 구현해야 함.
     * @param mode - 다음과 같은 옵션이 있는 열거형:
     *      opSucceeded - 사용자의 작업이 성공함.
     *      opReverted  - 사용자의 작업이 되돌려짐. 가스 요금을 여전히 지불해야 함.
     *      postOpReverted - 사용자의 작업이 성공했지만, postOp이 되돌려짐(opSucceeded 모드에서).
     *                       이 호출은 의도적으로 되돌린 후 2번째 호출됨.
     * @param context - validatePaymasterUserOp에서 반환된 context 값.
     * @param actualGasCost - 지금까지 사용된 실제 가스 양 (이 postOp 호출 제외).
     */
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal virtual {

        (mode,context,actualGasCost); // 사용되지 않은 파라미터
        // validatePaymasterUserOp이 context를 반환하면 이 메서드를 구현해야 함
        revert("must override");
    }

    /**
     * 트랜잭션 수수료 지불을 위해 이 페이마스터의 예치금을 추가.
     */
    function deposit() public payable {
        entryPoint.depositTo{value : msg.value}(address(this));
    }

    /**
     * 예치금에서 특정 금액을 인출.
     * @param withdrawAddress 인출할 주소.
     * @param amount 인출할 금액.
     */
    function withdrawTo(address payable withdrawAddress, uint256 amount) public onlyOwner {
        entryPoint.withdrawTo(withdrawAddress, amount);
    }

    /**
     * 이 페이마스터의 스테이크를 추가.
     * 이 메서드는 현재 스테이크에 이더를 추가할 수 있음.
     * @param unstakeDelaySec - 이 페이마스터의 언스테이크 지연 시간. 증가만 가능.
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value : msg.value}(unstakeDelaySec);
    }

    /**
     * entryPoint에 있는 현재 페이마스터의 예치금을 반환.
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    /**
     * 인출을 위해 스테이크를 잠금 해제.
     * 페이마스터는 언락 상태에서 addStake를 다시 호출할 때까지 요청을 처리할 수 없음.
     */
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    /**
     * 전체 페이마스터의 스테이크를 인출.
     * 스테이크는 먼저 언락되어야 함(그리고 언스테이크 지연 시간이 지나야 함).
     * @param withdrawAddress 인출 금액을 보낼 주소.
     */
    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(withdrawAddress);
    }

    /// 호출이 유효한 entryPoint에서 발생했는지 검증.
    function _requireFromEntryPoint() internal virtual {
        require(msg.sender == address(entryPoint), "Sender not EntryPoint");
    }
}
