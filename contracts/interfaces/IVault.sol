// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../lib/SharedStructs.sol";

interface IVault {
    event Deposit(address indexed from, bytes32 symbol, uint256 amount);
    event Withdrawal(
        address indexed from,
        bytes32 symbol,
        uint256 amount,
        uint256 proratedFee
    );
    event FeeCollection(uint timestamp, uint256 totalFee);
    event TokenBurn(address, uint256);
    event Whitelist(bytes32 symbol);

    error InvalidSignature();
    error UnevenArrays();
    error InvalidAnnualFee(uint256);
    error UnsupportedToken(bytes32 token);
    error InvalidAddress(address);
    error InvalidAmount(uint256);
    error InsuffientVaultFunds();
    error InsuffientAccountFunds();

    function adjustFee(uint256 _newAnnualFee) external;

    function deposit(bytes32 _symbol, uint256 _amount) external;

    function pause() external;

    function unpause() external;

    function whitelistToken(bytes32 _symbol, address _tokenAddress) external;

    function withdraw(
        SharedStructs.WithdrawRequest calldata _withdrawal,
        uint256 _toBurn,
        bytes32 _hash,
        bytes calldata _signature
    ) external;

    function withdrawFee(
        bytes32[] calldata _symbols
    ) external returns (uint256 totalFee);
}
