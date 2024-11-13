// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.12;

import "../interfaces/IStakeManager.sol";

/* solhint-disable avoid-low-level-calls */
/* solhint-disable not-rely-on-time */
/**
 * 예치금과 스테이크를 관리합니다.
 * 예치금은 UserOperations를 지불하는 데 사용되는 잔액입니다 (paymaster 또는 계정이 지불)
 * 스테이크는 paymaster에 의해 최소 "언스테이크 지연" 기간 동안 잠긴 값입니다.
 */
abstract contract StakeManager is IStakeManager {

    /// paymaster와 그들의 예치금 및 스테이크를 매핑합니다.
    mapping(address => DepositInfo) public deposits;

    /// @inheritdoc IStakeManager
    function getDepositInfo(address account) public view returns (DepositInfo memory info) {
        return deposits[account];
    }

    // 내부 메서드로, 오직 스테이크 정보만 반환합니다.
    function _getStakeInfo(address addr) internal view returns (StakeInfo memory info) {
        DepositInfo storage depositInfo = deposits[addr];
        info.stake = depositInfo.stake;
        info.unstakeDelaySec = depositInfo.unstakeDelaySec;
    }

    /// 계정의 예치금(가스 지불용)을 반환합니다.
    function balanceOf(address account) public view returns (uint256) {
        return deposits[account].deposit;
    }

    receive() external payable {
        depositTo(msg.sender);
    }

    function _incrementDeposit(address account, uint256 amount) internal {
        DepositInfo storage info = deposits[account];
        uint256 newAmount = info.deposit + amount;
        require(newAmount <= type(uint112).max, "deposit overflow");
        info.deposit = uint112(newAmount);
    }

    /**
     * 주어진 계정의 예치금을 추가합니다.
     */
    function depositTo(address account) public payable {
        _incrementDeposit(account, msg.value);
        DepositInfo storage info = deposits[account];
        emit Deposited(account, info.deposit);
    }

    /**
     * 계정의 스테이크에 금액과 지연을 추가합니다.
     * 모든 대기 중인 언스테이크는 먼저 취소됩니다.
     * @param unstakeDelaySec 예치금을 인출할 수 있기 전에 잠길 새 기간입니다.
     */
    function addStake(uint32 unstakeDelaySec) public payable {
        DepositInfo storage info = deposits[msg.sender];
        require(unstakeDelaySec > 0, "Unstake delay must be specified");
        require(unstakeDelaySec >= info.unstakeDelaySec, "Unstake delay cannot be reduced");
        uint256 stake = info.stake + msg.value;
        require(stake > 0, "Stake amount must be specified");
        require(stake <= type(uint112).max, "Stake overflow");
        deposits[msg.sender] = DepositInfo(
            info.deposit,
            true,
            uint112(stake),
            unstakeDelaySec,
            0
        );
        emit StakeLocked(msg.sender, stake, unstakeDelaySec);
    }

    /**
     * 스테이크를 잠금 해제하려고 시도합니다.
     * 값은 언스테이크 지연 기간이 지난 후 withdrawStake를 사용하여 인출할 수 있습니다.
     */
    function unlockStake() external {
        DepositInfo storage info = deposits[msg.sender];
        require(info.unstakeDelaySec != 0, "No stake present");
        require(info.staked, "Already unstaking");
        uint48 withdrawTime = uint48(block.timestamp) + info.unstakeDelaySec;
        info.withdrawTime = withdrawTime;
        info.staked = false;
        emit StakeUnlocked(msg.sender, withdrawTime);
    }


    /**
     * (잠금 해제된) 스테이크에서 인출합니다.
     * 먼저 unlockStake를 호출하고 언스테이크 지연 기간이 지나야 합니다.
     * @param withdrawAddress 인출할 값을 보낼 주소입니다.
     */
    function withdrawStake(address payable withdrawAddress) external {
        DepositInfo storage info = deposits[msg.sender];
        uint256 stake = info.stake;
        require(stake > 0, "No stake to withdraw");
        require(info.withdrawTime > 0, "Must call unlockStake() first");
        require(info.withdrawTime <= block.timestamp, "Unstake delay period has not passed yet");
        info.unstakeDelaySec = 0;
        info.withdrawTime = 0;
        info.stake = 0;
        emit StakeWithdrawn(msg.sender, withdrawAddress, stake);
        (bool success,) = withdrawAddress.call{value : stake}("");
        require(success, "Stake withdrawal failed");
    }

    /**
     * 예치금에서 인출합니다.
     * @param withdrawAddress 인출할 값을 보낼 주소입니다.
     * @param withdrawAmount 인출할 금액입니다.
     */
    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external {
        DepositInfo storage info = deposits[msg.sender];
        require(withdrawAmount <= info.deposit, "Withdrawal amount exceeds deposit");
        info.deposit = uint112(info.deposit - withdrawAmount);
        emit Withdrawn(msg.sender, withdrawAddress, withdrawAmount);
        (bool success,) = withdrawAddress.call{value : withdrawAmount}("");
        require(success, "Withdrawal failed");
    }
}
