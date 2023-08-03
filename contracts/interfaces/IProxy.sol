// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../lib/SharedStructs.sol";

interface IProxy {
    event TokenBurn(address, uint256);

    error InvalidSignature();

    error UnevenArrays();

    function getTokenBalance() external view returns (uint256);

    function getAccountBalance(
        address _account
    ) external view returns (uint256);

    function batchWithdraw(
        SharedStructs.WithdrawRequest[] calldata _withdrawals,
        uint256[] calldata _toBurn,
        bytes32[] calldata _hash,
        bytes[] calldata _signature
    ) external;

    function updateBalances(
        address[] calldata _accounts,
        uint256[] calldata _newBalances
    ) external;
}
