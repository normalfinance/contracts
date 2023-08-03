// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Interfaces
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVault.sol";

// Lib
import "./lib/SharedStructs.sol";

// Modules
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

// Upgradeable Modules
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";

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
    IVault,
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuard
{
    using ECDSA for bytes32;

    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    uint256 constant TEN_THOUSAND = 10000;
    uint256 constant ONE_YEAR = 31556952;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FEE_CONTROLLER_ROLE =
        keccak256("FEE_CONTROLLER_ROLE");

    address payable private _feeController;

    uint256 private _annualFee; // bps
    mapping(bytes32 => uint256) private _lastFeeWithdrawalDates;

    address private _indexToken;
    mapping(bytes32 => address) private _whitelistedTokens;
    mapping(bytes32 => uint256) private _tokenFeesToCollect;

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    // solhint-disable-next-line no-empty-blocks
    receive() external payable virtual {}

    function initialize(
        address _aPauser,
        address payable _aFeeController,
        address _anIndexTokenAddress,
        uint256 _anAnnualFee,
        bytes32[] memory _tokenSymbols,
        address[] memory _tokenAddresses
    ) public initializer {
        if (_anAnnualFee <= 0 || 5000 < _anAnnualFee)
            revert InvalidAnnualFee(_anAnnualFee);
        if (_tokenSymbols.length != _tokenAddresses.length)
            revert UnevenArrays();

        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, _aPauser);
        _grantRole(FEE_CONTROLLER_ROLE, _aFeeController);

        _feeController = _aFeeController;

        _annualFee = _anAnnualFee;

        _indexToken = _anIndexTokenAddress;

        for (uint256 i = 0; i < _tokenSymbols.length; ++i) {
            _whitelistedTokens[_tokenSymbols[i]] = _tokenAddresses[i];
            _tokenFeesToCollect[_tokenSymbols[i]] = 0;
            _lastFeeWithdrawalDates[_tokenSymbols[i]] = getOneMonthAgo();
        }
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns timestamp of one month ago in seconds.
    function getOneMonthAgo() public view virtual returns (uint) {
        return block.timestamp - (60 * 60 * 24 * 30);
    }

    /// @notice Returns the Vault fee.
    function getFee() public view virtual returns (uint256) {
        return _annualFee;
    }

    /// @notice Returns the timestamp when the last fee was collected.
    /// @param _symbol Desired token last fee withdrawal date
    function getLastFeeWithdrawalDate(
        bytes32 _symbol
    ) public view virtual returns (uint) {
        return _lastFeeWithdrawalDates[_symbol];
    }

    /// @notice Returns the outstanding fees to collect for a token.
    /// @param _symbol Desired token fees to collect
    function getTokenFeesToCollect(
        bytes32 _symbol
    ) public view virtual returns (uint) {
        return _tokenFeesToCollect[_symbol];
    }

    /// @notice Returns the token contract address.
    /// @param _symbol Desired token contract address
    function getWhitelistedToken(
        bytes32 _symbol
    ) public view virtual returns (address) {
        return _whitelistedTokens[_symbol];
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
    ) external whenNotPaused nonReentrant {
        if (_whitelistedTokens[_symbol] == address(0))
            revert UnsupportedToken(_symbol);
        if (_amount <= 0) revert InvalidAmount(_amount);

        IERC20(_whitelistedTokens[_symbol]).transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        emit Deposit(msg.sender, _symbol, _amount);
    }

    /// @notice Withdrawals tokens from the Vault
    /// @dev
    /// @param withdrawal ...
    /// @param _toBurn Quantity of Index Tokens to burn for withdrawal
    function withdraw(
        SharedStructs.WithdrawRequest calldata _withdrawal,
        uint256 _toBurn,
        bytes32 _hash,
        bytes calldata _signature
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        uint256 preGas = gasleft();

        if (_whitelistedTokens[_withdrawal.symbol] == address(0))
            revert UnsupportedToken(_withdrawal.symbol);
        if (_withdrawal.amount <= 0) revert InvalidAmount(_withdrawal.amount);
        if (
            _withdrawal.amount >
            IERC20(_whitelistedTokens[_withdrawal.symbol]).balanceOf(
                address(this)
            ) -
                _tokenFeesToCollect[_withdrawal.symbol]
        ) revert InsuffientVaultFunds();
        if (_withdrawal.to == address(0)) revert InvalidAddress(_withdrawal.to);
        if (
            _toBurn <= 0 ||
            _toBurn > IERC20(_indexToken).balanceOf(_withdrawal.owner)
        ) revert InsuffientAccountFunds();
        if (
            SignatureChecker.isValidSignatureNow(
                _withdrawal.owner,
                _hash,
                _signature
            ) == false
        ) revert InvalidSignature();

        // Calculate prorated fee
        uint256 timeDelta = block.timestamp -
            _lastFeeWithdrawalDates[_withdrawal.symbol];
        uint256 proratedFee = (((_annualFee * _withdrawal.amount) * timeDelta) /
            ONE_YEAR /
            TEN_THOUSAND);

        // Calculate gas cost of transaction
        uint256 actualGasCost = (preGas - gasleft()) * tx.gasprice;

        uint256 totalFee = proratedFee + actualGasCost;

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
        address _tokenAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_tokenAddress == address(0)) revert InvalidAddress(_tokenAddress);

        _whitelistedTokens[_symbol] = _tokenAddress;
        _tokenFeesToCollect[_symbol] = 0;
        _lastFeeWithdrawalDates[_symbol] = getOneMonthAgo();

        emit Whitelist(_symbol);
    }

    /// @notice Updates Vault annual fee
    /// @dev
    /// @param _newAnnualFee Updated annual basis points fee
    function adjustFee(
        uint256 _newAnnualFee
    ) external onlyRole(FEE_CONTROLLER_ROLE) {
        if (_newAnnualFee <= 0 || 5000 < _newAnnualFee)
            revert InvalidAnnualFee(_newAnnualFee);
        _annualFee = _newAnnualFee;
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
                        _feeController,
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
}
