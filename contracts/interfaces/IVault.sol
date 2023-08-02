// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IVault {
    struct WithdrawRequest {
        address owner;
        bytes32 symbol;
        uint256 amount;
        address payable to;
    }

    function adjustFee(uint256 _newAnnualFee) external;

    function deposit(bytes32 _symbol, uint256 _amount) external;

    function getFee() external view returns (uint256);

    function getLastFeeWithdrawalDate(
        bytes32 _symbol
    ) external view returns (uint256);

    function getOneMonthAgo() external view returns (uint256);

    function getTokenFeesToCollect(
        bytes32 _symbol
    ) external view returns (uint256);

    function getWhitelistedToken(
        bytes32 _symbol
    ) external view returns (address);

    function initialize(
        address _pauser,
        address _feeController,
        address _indexTokenAddress,
        uint256 _annualFee,
        bytes32[] calldata _tokenSymbols,
        address[] calldata _tokenAddresses
    ) external;

    function pause() external;

    function paused() external view returns (bool);

    function unpause() external;

    function whitelistToken(bytes32 _symbol, address _tokenAddress) external;

    function withdraw(
        WithdrawRequest calldata _withdrawal,
        uint256 _toBurn,
        bytes32 _hash,
        bytes calldata _signature
    ) external;

    function withdrawFee(
        bytes32[] calldata _symbols
    ) external returns (uint256 totalFee);
}
