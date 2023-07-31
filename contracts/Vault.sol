// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../node_modules/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../node_modules/@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";

//  /$$   /$$                                             /$$
// | $$$ | $$                                            | $$
// | $$$$| $$  /$$$$$$   /$$$$$$  /$$$$$$/$$$$   /$$$$$$ | $$
// | $$ $$ $$ /$$__  $$ /$$__  $$| $$_  $$_  $$ |____  $$| $$
// | $$  $$$$| $$  \ $$| $$  \__/| $$ \ $$ \ $$  /$$$$$$$| $$
// | $$\  $$$| $$  | $$| $$      | $$ | $$ | $$ /$$__  $$| $$
// | $$ \  $$|  $$$$$$/| $$      | $$ | $$ | $$|  $$$$$$$| $$
// |__/  \__/ \______/ |__/      |__/ |__/ |__/ \_______/|__/

/// @title
/// @author Joshua Blew <joshua@normalfinance.io>
/// @notice
/// @dev
contract Vault is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuard
{
    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FEE_CONTROLLER_ROLE =
        keccak256("FEE_CONTROLLER_ROLE");

    address payable private feeController;

    uint256 private annualFee; // bps
    uint private lastFeeWithdrawalDate;

    struct TokenInfo {
        address tokenAddress;
        AggregatorV3Interface priceFeed;
    }

    TokenInfo internal indexToken;
    mapping(bytes32 => TokenInfo) internal whitelistedTokens;

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

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    function initialize(
        address _pauser,
        address payable _feeController,
        address _indexTokenAddress,
        address _indexTokenPriceFeedAddress,
        uint256 _annualFee,
        bytes32[] memory _tokenSymbols,
        address[] memory _tokenAddresses,
        address[] memory _priceFeedAddresses
    ) public initializer {
        require(
            0 < _annualFee && _annualFee <= 50000000000000000,
            "Invalid annual fee"
        ); // b/t 0% and 5%
        require(
            _tokenSymbols.length == _tokenAddresses.length &&
                _tokenSymbols.length == _priceFeedAddresses.length,
            "Invalid address arrays"
        );

        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, _pauser);
        _grantRole(FEE_CONTROLLER_ROLE, _feeController);

        feeController = _feeController;

        annualFee = _annualFee;
        lastFeeWithdrawalDate = block.timestamp - (60 * 60 * 24 * 30); // now - 30 days

        indexToken = TokenInfo(
            _indexTokenAddress,
            AggregatorV3Interface(_indexTokenPriceFeedAddress)
        );

        for (uint256 i = 0; i < _tokenSymbols.length; ++i) {
            whitelistedTokens[_tokenSymbols[i]] = TokenInfo(
                _tokenAddresses[i],
                AggregatorV3Interface(_priceFeedAddresses[i])
            );
        }
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the Vault fee.
    function getFee() public view virtual returns (uint256) {
        return annualFee;
    }

    /// @notice Returns the timestamp when the last fee was collected.
    function getLastFeeWithdrawalDate() public view virtual returns (uint) {
        return lastFeeWithdrawalDate;
    }

    /// @notice Returns the ...
    function getWhitelistedTokenAddress(
        bytes32 _symbol
    ) public view virtual returns (address) {
        return whitelistedTokens[_symbol].tokenAddress;
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits tokens into the Vault
    /// @dev
    /// @param _symbol Desired token contract address
    /// @param _amount Number of tokens to deposit
    function deposit(
        bytes32 _symbol,
        uint256 _amount
    ) external payable whenNotPaused nonReentrant {
        require(
            whitelistedTokens[_symbol].tokenAddress != address(0),
            "Unsupported symbol"
        );
        require(_amount > 0, "Amount must be greater than zero");

        IERC20(whitelistedTokens[_symbol].tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        emit Deposit(msg.sender, _symbol, _amount);
    }

    /// @notice Withdrawals tokens from the Vault
    /// @dev
    /// @param _amount Number of Index Tokens to redeem
    /// @param _symbol Desired withdrawal token
    /// @param _destination Address to send withdrawal to
    function withdraw(
        uint256 _amount,
        bytes32 _symbol,
        address payable _destination
    ) external payable whenNotPaused nonReentrant {
        require(_amount > 0, "Amount must be greater than zero");
        require(
            whitelistedTokens[_symbol].tokenAddress != address(0),
            "Unsupported symbol"
        );
        require(_destination != address(0), "Invalid destination address");

        // Ensure msg.sender has adequate Index Token balance
        uint256 balance = IERC20(indexToken.tokenAddress).balanceOf(msg.sender);
        require(
            0 < balance && _amount <= balance,
            "Insufficient Index Token balance"
        );

        // Compare msg.sender Index Token holdings vs. withdrawal
        (, int256 indexTokenPrice, , , ) = indexToken
            .priceFeed
            .latestRoundData();
        uint256 withdrawalRequestValue = uint256(indexTokenPrice) * _amount;

        // Calculate withdrawal token quantity
        (, int256 symbolTokenPrice, , , ) = whitelistedTokens[_symbol]
            .priceFeed
            .latestRoundData();
        uint256 withdrawalTokenQuantiy = withdrawalRequestValue /
            uint256(symbolTokenPrice);

        // Ensure Vault can afford withdrawal
        require(
            withdrawalTokenQuantiy <=
                IERC20(whitelistedTokens[_symbol].tokenAddress).balanceOf(
                    address(this)
                ),
            "Insufficient Vault funds"
        );

        // Collect fee
        uint daysDiff = (block.timestamp - lastFeeWithdrawalDate) /
            60 /
            60 /
            24;
        uint256 proratedFee = (annualFee / 365) * daysDiff;
        IERC20(whitelistedTokens[_symbol].tokenAddress).transfer(
            feeController,
            withdrawalTokenQuantiy * proratedFee
        );

        // Send token to destination
        IERC20(whitelistedTokens[_symbol].tokenAddress).transfer(
            msg.sender,
            withdrawalTokenQuantiy * (1 - proratedFee)
        );
        emit Withdrawal(
            msg.sender,
            _symbol,
            withdrawalTokenQuantiy,
            proratedFee
        );

        // Burn Index Token
        ERC20BurnableUpgradeable(indexToken.tokenAddress).burn(_amount);
        emit TokenBurn(msg.sender, _amount);
    }

    /*///////////////////////////////////////////////////////////////
                        Admin functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses `whenNotPaused` functions for emergencies
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses `whenNotPaused` functions
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice
    function whitelistToken(
        bytes32 _symbol,
        address _tokenAddress,
        address _priceFeedAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_priceFeedAddress != address(0), "Invalid price feed address");

        whitelistedTokens[_symbol] = TokenInfo(
            _tokenAddress,
            AggregatorV3Interface(_priceFeedAddress)
        );

        emit Whitelist(_symbol);
    }

    /// @notice Updates Vault annual fee
    /// @dev
    /// @param _newAnnualFee Updated annual basis points fee
    function adjustFee(
        uint256 _newAnnualFee
    ) external onlyRole(FEE_CONTROLLER_ROLE) {
        require(
            0 < _newAnnualFee && _newAnnualFee <= 50000000000000000,
            "Invalid annual fee"
        ); // b/t 0% and 5%
        annualFee = _newAnnualFee;
    }

    /// @notice Withdraws Vault fee
    /// @dev
    /// @param _symbols List of token symbols to withdraw fees for
    /// @return totalFee
    function withdrawFee(
        bytes32[] memory _symbols
    )
        external
        onlyRole(FEE_CONTROLLER_ROLE)
        nonReentrant
        returns (uint256 totalFee)
    {
        uint _now = block.timestamp;
        // TODO: lastFeeWithdrawalDate does not track when each symbol's fee was collected
        uint daysDiff = (_now - lastFeeWithdrawalDate) / 60 / 60 / 24;

        for (uint256 i = 0; i < _symbols.length; ++i) {
            if (whitelistedTokens[_symbols[i]].tokenAddress != address(0)) {
                uint256 vaultBalance = IERC20(
                    whitelistedTokens[_symbols[i]].tokenAddress
                ).balanceOf(address(this));

                if (vaultBalance > 0) {
                    uint256 tokenFee = (annualFee / 365) *
                        daysDiff *
                        vaultBalance;

                    IERC20(whitelistedTokens[_symbols[i]].tokenAddress)
                        .transfer(feeController, tokenFee);

                    emit FeeCollection(_now, totalFee);

                    totalFee += tokenFee;
                }
            }
        }

        lastFeeWithdrawalDate = _now;
    }
}
