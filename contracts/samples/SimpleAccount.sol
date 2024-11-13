// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import "../core/BaseAccount.sol";
import "../interfaces/ISignAuthorizer.sol";
import "./callback/TokenCallbackHandler.sol";
import "../operator/IOperator.sol";

/**
  * 최소 계정.
  * 이 계정은 샘플 최소 계정입니다.
  * 실행 및 이더리움 처리 메서드를 가집니다.
  * EntryPoint를 통해 요청을 보낼 수 있는 단일 서명자를 가집니다.
  */
contract SimpleAccount is BaseAccount, TokenCallbackHandler, UUPSUpgradeable, Initializable, ISignAuthorizer {
    using ECDSA for bytes32;

    address public owner;

    address public operatorManager;

    mapping(address => bool) signerMap;

    IEntryPoint private immutable _entryPoint;

    mapping(address => bool) maintainerMap; // EOA (외부 소유 계정)

    event SimpleAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner);

    event ExchangeAccountChange(address indexed exchangeOwner, address indexed exchangeContract);

    event AddMaintainer(address indexed maintainer);

    event RemoveMaintainer(address indexed maintainer);

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    receive() external payable {}

    constructor(IEntryPoint anEntryPoint, address _operatorManager) {
        _entryPoint = anEntryPoint;
        operatorManager = _operatorManager;
        _disableInitializers();
    }

    // EOA 소유자 또는 계정 자체에서 직접 호출 (execute()를 통해 리디렉션됨)
    function _onlyOwner() internal view {    
        require(msg.sender == owner || msg.sender == address(this), "only owner");
    }

    function addMaintainer(address _maintainer) external onlyOwner {
        maintainerMap[_maintainer] = true;
        emit AddMaintainer(_maintainer);
    }

    function removeMaintainer(address _maintainer) external onlyOwner {
        maintainerMap[_maintainer] = false;
        emit RemoveMaintainer(_maintainer);
    }

    /**
     * 트랜잭션 실행 (소유자 또는 EntryPoint에서 직접 호출됨)
     */
    function execute(address dest, uint256 value, bytes calldata func) external {
        _requireFromEntryPointOrOwner();
        _call(dest, value, func);
    }

    /**
     * 트랜잭션 일괄 실행
     */
    function executeBatch(address[] calldata dest, bytes[] calldata func) external {
        _requireFromEntryPointOrOwner();
        require(dest.length == func.length, "wrong array lengths");
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], 0, func[i]);
        }
    }

    /**
     * @dev _entryPoint 멤버는 가스 비용 절감을 위해 불변으로 설정됩니다. EntryPoint를 업그레이드하려면,
     * SimpleAccount의 새로운 구현을 배포한 후 새로운 EntryPoint 주소로 업그레이드해야 합니다.
     * 그 후 `upgradeTo()`를 호출하여 구현을 업그레이드합니다.
     */
    function initialize(address anOwner, address _operatorManager) public virtual initializer {
        _initialize(anOwner, _operatorManager);
        signerMap[anOwner] = true;
    }

    function _initialize(address anOwner, address _operatorManager) internal virtual {
        owner = anOwner;
        operatorManager = _operatorManager;
        emit SimpleAccountInitialized(_entryPoint, owner);
    }

    // EntryPoint, 소유자, 운영자 또는 유지보수자로부터 호출되었는지 확인
    function _requireFromEntryPointOrOwner() internal view {
        require(msg.sender == address(entryPoint())
        || msg.sender == owner
        || IOperator(operatorManager).isOperator(msg.sender) || maintainerMap[msg.sender], "account: not Owner or EntryPoint");
    }

    /// BaseAccount의 템플릿 메서드 구현
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
    internal override virtual returns (uint256 validationData) {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        if (owner != hash.recover(userOp.signature))
            return SIG_VALIDATION_FAILED;
        return 0;
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value : value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * EntryPoint에서 현재 계정의 예치금 확인
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /**
     * 이 계정의 EntryPoint에 더 많은 자금을 예치
     */
    function addDeposit() public payable {
        entryPoint().depositTo{value : msg.value}(address(this));
    }

    /**
     * 계정의 예치금에서 인출
     * @param withdrawAddress 인출할 대상 주소
     * @param amount 인출할 금액
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlyOwner {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        _onlyOwner();
    }

    function isAuthorizedSigner(address signer) external view override returns (bool){
        return signerMap[signer];
    }
}
