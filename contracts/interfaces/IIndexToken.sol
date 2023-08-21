// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IIndexToken {
    error InvalidSignature();

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function MINTER_ROLE() external view returns (bytes32);

    function PAUSER_ROLE() external view returns (bytes32);

    function SNAPSHOT_ROLE() external view returns (bytes32);

    function VAULT_ROLE() external view returns (bytes32);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function burn(uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;

    function decimals() external view returns (uint8);

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) external returns (bool);

    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string calldata name,
            string calldata version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] calldata extensions
        );

    function getProxy() external view returns (address);

    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool);

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) external returns (bool);

    function initialize(
        string calldata _name,
        string calldata _symbol,
        address _proxyAddress
    ) external;

    function mint(address _to, uint256 _amount) external;

    function mintToProxy(uint256 _amount) external;

    function mintWithAllowance(
        uint256 _amount,
        address[] calldata _accounts,
        uint256[] calldata _investments
    ) external;

    function name() external view returns (string memory);

    function nonces(address owner) external view returns (uint256);

    function pause() external;

    function paused() external view returns (bool);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function renounceRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function symbol() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function unpause() external;
}
