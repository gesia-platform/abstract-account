// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable reason-string */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../core/BasePaymaster.sol";

/**
 * 이 예제 paymaster는 가스를 지불하는 토큰으로 자신을 정의합니다.
 * paymaster는 외부 계약을 사용할 수 없기 때문에 paymaster 자체가 토큰이 되어야 합니다.
 * 또한 환율은 고정되어야 하며, 외부 Uniswap 또는 다른 교환 계약을 참조할 수 없습니다.
 * 서브클래스는 "getTokenValueOfEth"를 재정의하여 실제 토큰 환율을 제공하고, 이는 소유자가 설정할 수 있습니다.
 * 알려진 제한 사항: 이 paymaster는 여러 작업이 배치로 수행될 때 악용될 수 있습니다 (다른 계정의 작업):
 * - 단일 작업은 paymaster를 악용할 수 없습니다 (postOp가 토큰을 인출하지 못하면 사용자의 작업이 되돌려지고,
 *   그런 다음 토큰을 인출할 수 있음을 알 수 있습니다), 그러나 서로 다른 발신자가 사용하는 여러 작업이 배치에서
 *   수행되면 2번째 이후의 작업에서 자금을 인출할 수 있으며, 이는 paymaster가 자신의 예금에서 비용을 지불하게 만듭니다.
 * - 가능한 해결 방법은 더 복잡한 paymaster 체계를 사용하는 것 (예: DepositPaymaster) 또는 계정과 호출된 메서드 ID를 화이트리스트에 추가하는 것입니다.
 */
contract LegacyTokenPaymaster is BasePaymaster, ERC20 {

    // postOp의 계산된 비용
    uint256 constant public COST_OF_POST = 15000;

    address public immutable theFactory;

    constructor(address accountFactory, string memory _symbol, IEntryPoint _entryPoint) ERC20(_symbol, _symbol) BasePaymaster(_entryPoint) {
        theFactory = accountFactory;
        // 공백이 아니도록 설정
        _mint(address(this), 1);

        // 소유자는 paymaster의 잔액에서 토큰을 인출할 수 있습니다.
        _approve(address(this), msg.sender, type(uint).max);
    }

    /**
     * 소유자를 위한 헬퍼 함수, 토큰을 발행하고 인출합니다.
     * @param recipient - 발행된 토큰을 받을 주소.
     * @param amount - 받을 토큰의 양.
     */
    function mintTokens(address recipient, uint256 amount) external onlyOwner {
        _mint(recipient, amount);
    }

    /**
     * paymaster의 소유권을 이전합니다.
     * 이 paymaster의 소유자는 (paymaster의 잔액으로 전송된) 자금을 인출할 수 있습니다.
     * 소유자를 변경하면 이전 소유자의 인출 권한은 취소됩니다.
     */
    function transferOwnership(address newOwner) public override virtual onlyOwner {
        // 현재 소유자의 허용을 제거
        _approve(address(this), owner(), 0);
        super.transferOwnership(newOwner);
        // 새 소유자는 paymaster의 잔액에서 토큰을 인출할 수 있습니다.
        _approve(address(this), newOwner, type(uint).max);
    }

    // 주의: 이 메서드는 고정된 비율의 토큰-이더를 가정합니다. 서브클래스는 oracle을 제공하거나 설정할 수 있는 setter를 공급해야 합니다.
    function getTokenValueOfEth(uint256 valueEth) internal view virtual returns (uint256 valueToken) {
        return valueEth / 100;
    }

    /**
      * 요청을 검증합니다:
      * 만약 이것이 생성자 호출이라면, 그것이 알려진 계정인지 확인합니다.
      * 발신자가 충분한 토큰을 가지고 있는지 확인합니다.
      * (paymaster가 토큰이기 때문에 "승인"이라는 개념은 없습니다)
      */
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 /*userOpHash*/, uint256 requiredPreFund)
    internal view override returns (bytes memory context, uint256 validationData) {
        uint256 tokenPrefund = getTokenValueOfEth(requiredPreFund);

        // verificationGasLimit는 postOp의 가스 한도로도 사용됩니다. 충분히 높게 설정되어 있는지 확인합니다.
        // postOp를 처리할 수 있을 만큼 verificationGasLimit이 충분히 높은지 확인합니다.
        require(userOp.verificationGasLimit > COST_OF_POST, "TokenPaymaster: gas too low for postOp");

        if (userOp.initCode.length != 0) {
            _validateConstructor(userOp);
            require(balanceOf(userOp.sender) >= tokenPrefund, "TokenPaymaster: no balance (pre-create)");
        } else {
            require(balanceOf(userOp.sender) >= tokenPrefund, "TokenPaymaster: no balance");
        }

        return (abi.encode(userOp.sender), 0);
    }

    // 계정을 생성할 때, 생성자 코드와 매개변수를 검증합니다.
    // 우리는 우리 factory를 신뢰합니다 (그리고 다른 공개 메서드가 없다는 것을 확인합니다)
    function _validateConstructor(UserOperation calldata userOp) internal virtual view {
        address factory = address(bytes20(userOp.initCode[0 : 20]));
        require(factory == theFactory, "TokenPaymaster: wrong account factory");
    }

    /**
     * 사용자의 실제 요금 부과.
     * 이 메서드는 사용자의 트랜잭션이 mode==OpSucceeded|OpReverted일 때 호출됩니다 (계정은 두 경우 모두 지불합니다).
     * 그러나 사용자가 잔액을 변경하여 postOp가 되돌려지게 만든다면, 그 후 다시 호출되며,
     * 이때는 트랜잭션이 성공해야 합니다 (사용자의 트랜잭션이 되돌려지기 전에 validatePaymasterUserOp에서 상태가 복원됩니다).
     */
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal override {
        // 우리는 실제로 모드에 관심이 없습니다. 사용자의 토큰으로 가스를 지불합니다.
        (mode);
        address sender = abi.decode(context, (address));
        uint256 charge = getTokenValueOfEth(actualGasCost + COST_OF_POST);
        // actualGasCost는 위에서 요구된 preFund보다 크지 않으므로, 전송은 성공해야 합니다.
        _transfer(sender, address(this), charge);
    }
}
