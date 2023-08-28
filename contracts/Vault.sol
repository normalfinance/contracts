// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Modules
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Lib
import "./lib/SharedStructs.sol";

// Interfaces
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//  /$$   /$$                                             /$$
// | $$$ | $$                                            | $$
// | $$$$| $$  /$$$$$$   /$$$$$$  /$$$$$$/$$$$   /$$$$$$ | $$
// | $$ $$ $$ /$$__  $$ /$$__  $$| $$_  $$_  $$ |____  $$| $$
// | $$  $$$$| $$  \ $$| $$  \__/| $$ \ $$ \ $$  /$$$$$$$| $$
// | $$\  $$$| $$  | $$| $$      | $$ | $$ | $$ /$$__  $$| $$
// | $$ \  $$|  $$$$$$/| $$      | $$ | $$ | $$|  $$$$$$$| $$
// |__/  \__/ \______/ |__/      |__/ |__/ |__/ \_______/|__/

error InvalidSignature();
error UnevenArrays();
error InvalidAnnualFee(uint256);
error UnsupportedToken(bytes32 token);
error InvalidAddress(address);

/// @title Vault contract
/// @author Joshua Blew <joshua@normalfinance.io>
/// @notice Holds deposits for crypto funds and enables authorized withdrawals
contract Vault is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard
{
    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    uint256 constant TEN_THOUSAND = 10000;
    uint256 constant ONE_YEAR = 31556952;

    uint256 private _annualFee;
    mapping(bytes32 => uint256) private _lastFeeWithdrawalDates;

    mapping(bytes32 => address) private _whitelistedTokens;
    mapping(bytes32 => uint256) private _tokenFeesToCollect;

    mapping(bytes => bool) public seenWithdrawalSignatures;

    event Withdrawal(
        address indexed from,
        bytes32 symbol,
        uint256 amount,
        uint256 proratedFee
    );
    event FeeCollection(uint timestamp, uint256 totalFee);
    event Whitelist(bytes32 symbol);

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    // solhint-disable-next-line no-empty-blocks
    receive() external payable virtual {}

    /// @notice Initializes the contract after deployment
    /// @dev Replaces the constructor() to support upgradeability (https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable)
    /// @param _anAnnualFee The Basis Point fee applied to all deposits
    /// @param _tokenSymbols List of supported tokens
    /// @param _tokenAddresses List of supported token addresses
    function initialize(
        uint256 _anAnnualFee,
        bytes32[] memory _tokenSymbols,
        address[] memory _tokenAddresses
    ) public initializer {
        if (_anAnnualFee <= 0 || 5000 < _anAnnualFee)
            revert InvalidAnnualFee(_anAnnualFee);
        if (_tokenSymbols.length != _tokenAddresses.length)
            revert UnevenArrays();

        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        _annualFee = _anAnnualFee;

        for (uint256 i = 0; i < _tokenSymbols.length; ++i) {
            _whitelistedTokens[_tokenSymbols[i]] = _tokenAddresses[i];
            _tokenFeesToCollect[_tokenSymbols[i]] = 0;
            _lastFeeWithdrawalDates[_tokenSymbols[i]] = getOneMonthAgo();
        }
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the Vault fee
    function getFee() public view virtual returns (uint256) {
        return _annualFee;
    }

    /// @notice Returns the timestamp when the last fee was collected
    /// @param _symbol Desired token last fee withdrawal date
    function getLastFeeWithdrawalDate(
        bytes32 _symbol
    ) public view virtual returns (uint) {
        return _lastFeeWithdrawalDates[_symbol];
    }

    /// @notice Returns the outstanding fees to collect for a token
    /// @param _symbol Desired token fees to collect
    function getTokenFeesToCollect(
        bytes32 _symbol
    ) public view virtual returns (uint) {
        return _tokenFeesToCollect[_symbol];
    }

    /// @notice Returns the token contract address
    /// @param _symbol Desired token contract address
    function getWhitelistedToken(
        bytes32 _symbol
    ) public view virtual returns (address) {
        return _whitelistedTokens[_symbol];
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdrawals tokens from the Vault
    /// @param _withdrawal Withdrawal info
    /// @param _hash Message hash of withdrawal
    /// @param _signature Withdrawal owner signature of withdrawal
    function withdraw(
        SharedStructs.WithdrawRequest memory _withdrawal,
        bytes32 _hash,
        bytes memory _signature
    ) external onlyOwner nonReentrant {
        if (
            !SignatureChecker.isValidSignatureNow(
                _withdrawal.owner,
                _hash,
                _signature
            )
        ) revert InvalidSignature();

        require(
            !seenWithdrawalSignatures[_signature],
            "Vault: Withdrawal already processed"
        );
        seenWithdrawalSignatures[_signature] = true;

        _withdraw(_withdrawal);
    }

    /*///////////////////////////////////////////////////////////////
                        Owner functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses `whenNotPaused` functions for emergencies
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpauses `whenNotPaused` functions
    function unpause() public onlyOwner {
        _unpause();
    }

    /// @notice Adds support for a new token
    /// @param _symbol The token symbol
    /// @param _tokenAddress The contract address of the token
    function whitelistToken(
        bytes32 _symbol,
        address _tokenAddress
    ) external onlyOwner {
        if (_tokenAddress == address(0)) revert InvalidAddress(_tokenAddress);

        _whitelistedTokens[_symbol] = _tokenAddress;
        _tokenFeesToCollect[_symbol] = 0;
        _lastFeeWithdrawalDates[_symbol] = getOneMonthAgo();

        emit Whitelist(_symbol);
    }

    /// @notice Updates the annual fee
    /// @param _newAnnualFee Updated annual basis points fee
    function adjustFee(uint256 _newAnnualFee) external onlyOwner {
        if (_newAnnualFee <= 0 || 5000 < _newAnnualFee)
            revert InvalidAnnualFee(_newAnnualFee);
        _annualFee = _newAnnualFee;
    }

    /// @notice Withdraws Vault fee
    /// @param _symbols List of token symbols to withdraw fees for
    /// @return totalFee
    function withdrawFee(
        bytes32[] calldata _symbols
    ) external onlyOwner nonReentrant returns (uint256 totalFee) {
        uint _now = block.timestamp;

        for (uint256 i = 0; i < _symbols.length; ++i) {
            if (_whitelistedTokens[_symbols[i]] != address(0)) {
                uint256 vaultBalance = IERC20(_whitelistedTokens[_symbols[i]])
                    .balanceOf(address(this));

                if (vaultBalance > 0) {
                    uint256 timeDelta = block.timestamp -
                        _lastFeeWithdrawalDates[_symbols[i]];

                    uint256 tokenFee = (((_annualFee * vaultBalance) *
                        timeDelta) /
                        ONE_YEAR /
                        TEN_THOUSAND);

                    IERC20(_whitelistedTokens[_symbols[i]]).transfer(
                        owner(),
                        tokenFee + _tokenFeesToCollect[_symbols[i]]
                    );

                    emit FeeCollection(_now, totalFee);

                    totalFee += tokenFee;

                    _tokenFeesToCollect[_symbols[i]] = 0;

                    _lastFeeWithdrawalDates[_symbols[i]] = _now;
                }
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdraws tokens stored in the Vault
    /// @param _withdrawal Withdrawal request
    function _withdraw(
        SharedStructs.WithdrawRequest memory _withdrawal
    ) internal {
        if (_whitelistedTokens[_withdrawal.symbol] == address(0))
            revert UnsupportedToken(_withdrawal.symbol);

        // Calculate prorated fee
        uint256 timeDelta = block.timestamp -
            _lastFeeWithdrawalDates[_withdrawal.symbol];
        uint256 proratedFee = (((_annualFee * _withdrawal.amount) * timeDelta) /
            ONE_YEAR /
            TEN_THOUSAND);

        uint256 totalFee = proratedFee;

        // Record fee for delayed collection
        _tokenFeesToCollect[_withdrawal.symbol] += totalFee;

        // Send token to destination
        IERC20(_whitelistedTokens[_withdrawal.symbol]).transfer(
            _withdrawal.to,
            _withdrawal.amount - totalFee
        );
        emit Withdrawal(
            _withdrawal.owner,
            _withdrawal.symbol,
            _withdrawal.amount,
            proratedFee
        );
    }

    /// @notice Returns timestamp of one month ago in seconds
    function getOneMonthAgo() internal view virtual returns (uint) {
        return block.timestamp - (60 * 60 * 24 * 30);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
