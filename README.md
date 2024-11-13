# Abstract Account

### 1. AccountFactory for Deploying User AA Accounts

An AccountFactory is created to deploy the AA (Abstract Account) for users.

```solidity
constructor(IEntryPoint _entryPoint, address _operatorManager) {
    accountImplementation = new SimpleAccount(_entryPoint, _operatorManager);
    operatorManager = _operatorManager;
}
```

### 2. User AA Account Deployment during Sign-Up

When a user signs up in the CarbonMonster app, an AA account is created for the user. The process is as follows:

2-1. The getAddress function is called to check if a smart contract is already deployed at the target address.

2-2. Within getAddress, the computeAddress method of Create2 is used to calculate the address by combining the salt and the contract byte code hash.

2-3. If an Abstract Account is already deployed at that address, the address is returned.

2-4. If an Abstract Account is not deployed at the address, a new account is deployed in the form of a proxy using the ERC1967 Proxy contract, and this address is returned.

```solidity
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

function getAddress(address owner, uint256 salt) public view returns (address) {
    return Create2.computeAddress(bytes32(salt), keccak256(abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                address(accountImplementation),
                abi.encodeCall(SimpleAccount.initialize, (owner, operatorManager))
            )
        )));
}
```

### 3. Multiple Administrators for CA Account

The CarbonMonster admin account is set as the main owner.

```solidity
function _onlyOwner() internal view {    
    require(msg.sender == owner || msg.sender == address(this), "only owner");
}
```

The EOA account created in the NetZero wallet is added to the maintainerMap of the user’s CA account.

```solidity
function addMaintainer(address _maintainer) external onlyOwner {
    maintainerMap[_maintainer] = true;
    emit AddMaintainer(_maintainer);
}

function removeMaintainer(address _maintainer) external onlyOwner {
    maintainerMap[_maintainer] = false;
    emit RemoveMaintainer(_maintainer);
}
```

The exchange operator account is designated as an operator, with the authority to perform token transfer-related functions exclusively for buy/sell transactions on the exchange.

```solidity
function addOperator(address _account) external onlyOwner {
    operatorMap[_account] = true;
    emit AddOperator(_account);
}

function removeOperator(address _account) external onlyOwner {
    operatorMap[_account] = false;
    emit RemoveOperator(_account);
}

function isOperator(address _account) external view override returns (bool) {
    return operatorMap[_account];
}
```

### 4. EOA Account Modification Is Limited to the CarbonMonster Admin Account

Only the CarbonMonster admin account can modify the EOA account.
In case a user requests to change the maintainerMap due to reasons like a lost EOA account, they can request ownership modification of the AA through the CarbonMonster admin account.

### 5. The Execute Function Is Used for NFT Transfers and Exchange Transactions

Users of the AA account can call the execute method directly to interact with external contracts.
In the case of transactions on the exchange, trades (buy/sell) are conducted through the admin account, allowing the user to trade without directly paying transaction fees.

```solidity
function execute(address dest, uint256 value, bytes calldata func) external {
    _requireFromEntryPointOrOwner();
    _call(dest, value, func);
}

function executeBatch(address[] calldata dest, bytes[] calldata func) external {
    _requireFromEntryPointOrOwner();
    require(dest.length == func.length, "wrong array lengths");
    for (uint256 i = 0; i < dest.length; i++) {
        _call(dest[i], 0, func[i]);
    }
}
```
