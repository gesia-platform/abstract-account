// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable reason-string */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../core/BasePaymaster.sol";
import "./IOracle.sol";

/**
 * 토큰 기반 paymaster로, 토큰 입금을 받음
 * 입금은 사용자 토큰 잔액을 사용하여 결제하는 보호 장치일 뿐임.
 * 사용자가 paymaster에 대한 승인을 하지 않았거나, 토큰 잔액이 부족할 경우 입금이 사용됨.
 * 따라서 필요한 입금은 하나의 메소드 호출만큼만 커버하면 됨.
 * 입금은 현재 블록에 대해 잠겨 있음: 사용자는 unlockTokenDeposit()을 호출해야 인출할 수 있음.
 * (하지만 이 입금을 사용하여 추가 작업을 진행할 수 없음)
 *
 * paymasterAndData는 paymaster 주소와 사용될 토큰 주소를 포함함.
 * @notice 이 paymaster는 EIP4337의 표준 규칙에 의해 거부될 수 있음, 외부 오라클을 사용하기 때문임.
 * (표준 규칙은 외부 계약의 데이터를 접근하는 것을 금지함)
 * "whitelisted"된 bundler만 사용할 수 있음.
 * (기술적으로 "oracle"이 사용될 수 있으며, 이는 저장소를 접근하지 않고 정적 값을 반환함)
 */
contract DepositPaymaster is BasePaymaster {

    using UserOperationLib for UserOperation;
    using SafeERC20 for IERC20;

    // postOp의 계산된 비용
    uint256 constant public COST_OF_POST = 35000;

    IOracle private constant NULL_ORACLE = IOracle(address(0));
    mapping(IERC20 => IOracle) public oracles;
    mapping(IERC20 => mapping(address => uint256)) public balances;
    mapping(address => uint256) public unlockBlock;

    constructor(IEntryPoint _entryPoint) BasePaymaster(_entryPoint) {
        // 소유자 계정은 잠금 해제되어, 지급된 토큰을 인출할 수 있음
        unlockTokenDeposit();
    }

    /**
     * paymaster의 소유자는 지원되는 토큰을 추가해야 함
     */
    function addToken(IERC20 token, IOracle tokenPriceOracle) external onlyOwner {
        require(oracles[token] == NULL_ORACLE, "Token already set");
        oracles[token] = tokenPriceOracle;
    }

    /**
     * 특정 계정이 가스를 지불할 수 있도록 토큰을 입금함.
     * 송신자는 먼저 이 paymaster가 이 토큰을 인출할 수 있도록 승인해야 함 (이 메소드에서만 인출됨).
     * 토큰을 입금하는 것은 "계정"에 이 토큰을 전송하는 것과 같으며, 이후 계정만이 이 토큰을 사용하여 가스를 지불하거나 withdrawTo()를 사용할 수 있음.
     *
     * @param token 입금할 토큰.
     * @param account 입금을 받을 계정.
     * @param amount 입금할 토큰의 양.
     */
    function addDepositFor(IERC20 token, address account, uint256 amount) external {
        require(oracles[token] != NULL_ORACLE, "unsupported token");
        //(송신자는 paymaster에 대한 승인이 필요함)
        token.safeTransferFrom(msg.sender, address(this), amount);
        balances[token][account] += amount;
        if (msg.sender == account) {
            lockTokenDeposit();
        }
    }

    /**
     * @return amount - 해당 토큰이 paymaster에 입금된 양.
     * @return _unlockBlock - 입금을 인출할 수 있는 블록 높이.
     */
    function depositInfo(IERC20 token, address account) public view returns (uint256 amount, uint256 _unlockBlock) {
        amount = balances[token][account];
        _unlockBlock = unlockBlock[account];
    }

    /**
     * 입금을 잠금 해제하여 인출할 수 있도록 함.
     * withdrawTo()와 같은 블록에서 호출할 수 없음.
     */
    function unlockTokenDeposit() public {
        unlockBlock[msg.sender] = block.number;
    }

    /**
     * 이 계정에 입금된 토큰을 잠그고 가스를 지불하는 데 사용할 수 있도록 함.
     * unlockTokenDeposit() 호출 후, 계정은 이 paymaster를 사용할 수 없도록 잠금이 해제될 때까지 기다려야 함.
     */
    function lockTokenDeposit() public {
        unlockBlock[msg.sender] = 0;
    }

    /**
     * 토큰을 인출함.
     * 이전 블록에서 unlock()이 호출된 후에만 호출할 수 있음.
     * @param token 인출할 토큰 입금.
     * @param target 전송할 주소.
     * @param amount 인출할 양.
     */
    function withdrawTokensTo(IERC20 token, address target, uint256 amount) public {
        require(unlockBlock[msg.sender] != 0 && block.number > unlockBlock[msg.sender], "DepositPaymaster: must unlockTokenDeposit");
        balances[token][msg.sender] -= amount;
        token.safeTransfer(target, amount);
    }

    /**
     * 주어진 eth 값을 토큰 양으로 변환
     * @param token 사용할 토큰.
     * @param ethBought 원하는 eth 값.
     * @return requiredTokens 필요한 토큰 양.
     */
    function getTokenValueOfEth(IERC20 token, uint256 ethBought) internal view virtual returns (uint256 requiredTokens) {
        IOracle oracle = oracles[token];
        require(oracle != NULL_ORACLE, "DepositPaymaster: unsupported token");
        return oracle.getTokenValueOfEth(ethBought);
    }

    /**
     * 요청을 검증:
     * 송신자는 최대 비용을 지불할 수 있는 충분한 입금을 가져야 함.
     * 송신자의 잔액은 확인하지 않음. 잔액이 부족할 경우 이 입금이 paymaster에게 거래 비용을 보상하기 위해 사용됨.
     */
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
    internal view override returns (bytes memory context, uint256 validationData) {

        (userOpHash);
        // verificationGasLimit은 postOp를 위한 가스 제한으로 이중 역할을 하므로 충분히 높은지 확인.
        require(userOp.verificationGasLimit > COST_OF_POST, "DepositPaymaster: gas too low for postOp");

        bytes calldata paymasterAndData = userOp.paymasterAndData;
        require(paymasterAndData.length == 20+20, "DepositPaymaster: paymasterAndData must specify token");
        IERC20 token = IERC20(address(bytes20(paymasterAndData[20:])));
        address account = userOp.getSender();
        uint256 maxTokenCost = getTokenValueOfEth(token, maxCost);
        uint256 gasPriceUserOp = userOp.gasPrice();
        require(unlockBlock[account] == 0, "DepositPaymaster: deposit not locked");
        require(balances[token][account] >= maxTokenCost, "DepositPaymaster: deposit too low");
        return (abi.encode(account, token, gasPriceUserOp, maxTokenCost, maxCost),0);
    }

    /**
     * 후속 작업을 수행하여 송신자에게 가스 비용을 청구.
     * 정상 모드에서는 transferFrom을 사용하여 송신자 잔액에서 충분한 토큰을 인출.
     * transferFrom이 실패할 경우, _postOp가 revert되며 entryPoint가 다시 호출.
     * 이 경우, 입금을 사용하여 지불 (유효한 입금이 충분한지 이미 확인됨)
     */
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal override {

        (address account, IERC20 token, uint256 gasPricePostOp, uint256 maxTokenCost, uint256 maxCost) = abi.decode(context, (address, IERC20, uint256, uint256, uint256));
        // 검증에 사용된 동일한 변환 비율을 사용.
        uint256 actualTokenCost = (actualGasCost + COST_OF_POST * gasPricePostOp) * maxTokenCost / maxCost;
        if (mode != PostOpMode.postOpReverted) {
            // 토큰으로 지불 시도:
            token.safeTransferFrom(account, address(this), actualTokenCost);
        } else {
            // 위의 transferFrom 실패 시, 입금을 사용하여 지불:
            balances[token][account] -= actualTokenCost;
        }
        balances[token][owner()] += actualTokenCost;
    }
}
