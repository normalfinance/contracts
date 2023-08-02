// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IProxy {
    struct WithdrawRequest {
        address owner;
        bytes32 symbol;
        uint256 amount;
        address payable to;
    }

    function balances(address) external view returns (uint256);

    function batchWithdraw(
        WithdrawRequest[] calldata _withdrawals,
        uint256[] calldata _toBurn,
        bytes32[] calldata _hash,
        bytes[] calldata _signature
    ) external;

    function getBalance(address _account) external view returns (uint256);

    function getTotalBalance() external view returns (uint256);

    function getVault() external view returns (address);

    function indexTokenAddress() external view returns (address);

    function initialize(
        address _indexTokenAddress,
        address _vaultAddress
    ) external;

    function updateBalances(
        address[] calldata _accounts,
        uint256[] calldata _investments
    ) external;
}
