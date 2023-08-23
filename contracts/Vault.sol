// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Interfaces
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Lib
import "./lib/SharedStructs.sol";

// Modules
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

// Upgradeable Modules
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Wormhole
import "../lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol";
import "../lib/wormhole-solidity-sdk/src/interfaces/IWormholeReceiver.sol";

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

/// @title
/// @author Joshua Blew <joshua@normalfinance.io>
/// @notice
/// @dev
contract Vault is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard,
    IWormholeReceiver
{
    using ECDSA for bytes32;

    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    uint256 constant TEN_THOUSAND = 10000;
    uint256 constant ONE_YEAR = 31556952;

    uint256 private _annualFee; // bps
    mapping(bytes32 => uint256) private _lastFeeWithdrawalDates;

    mapping(bytes32 => address) private _whitelistedTokens;
    mapping(bytes32 => uint256) private _tokenFeesToCollect;

    IWormholeRelayer public wormholeRelayer;
    mapping(bytes32 => bool) public seenDeliveryVaaHashes;

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

    function initialize(
        uint256 _anAnnualFee,
        bytes32[] memory _tokenSymbols,
        address[] memory _tokenAddresses,
        address _wormholeRelayer
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

        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
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

    /// @notice Returns the _account balance.
    function getTokenBalance(
        address _tokenAddress
    ) public view virtual returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory, // additionalVaas
        bytes32, // address that called 'sendPayloadToEvm' (HelloWormhole contract address)
        uint16 sourceChain,
        bytes32 deliveryHash
    ) public payable override {
        require(msg.sender == address(wormholeRelayer), "Only relayer allowed");

        // Ensure no duplicate deliveries
        require(
            !seenDeliveryVaaHashes[deliveryHash],
            "Message already processed"
        );
        seenDeliveryVaaHashes[deliveryHash] = true;

        // Parse the payload and do the corresponding actions!
        (
            SharedStructs.WithdrawRequest memory _withdrawal,
            bytes32 _hash,
            bytes memory _signature
        ) = abi.decode(
                payload,
                (SharedStructs.WithdrawRequest, bytes32, bytes)
            );

        _withdraw(_withdrawal, _hash, _signature);
    }

    /// @notice Withdrawals tokens from the Vault
    /// @dev
    /// @param withdrawal ...
    function withdraw(
        SharedStructs.WithdrawRequest calldata _withdrawal,
        bytes32 _hash,
        bytes calldata _signature
    ) external onlyOwner nonReentrant {
        _withdraw(_withdrawal, _hash, _signature);
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

    /// @notice
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

    /// @notice Updates Vault annual fee
    /// @dev
    /// @param _newAnnualFee Updated annual basis points fee
    function adjustFee(uint256 _newAnnualFee) external onlyOwner {
        if (_newAnnualFee <= 0 || 5000 < _newAnnualFee)
            revert InvalidAnnualFee(_newAnnualFee);
        _annualFee = _newAnnualFee;
    }

    /// @notice Withdraws Vault fee
    /// @dev
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

    /// @notice
    /// @dev
    /// @param _withdrawal Withdrawal requests
    /// @param _hash ...
    /// @param _signature ...
    function _withdraw(
        SharedStructs.WithdrawRequest memory _withdrawal,
        bytes32 _hash,
        bytes memory _signature
    ) internal {
        uint256 preGas = gasleft();

        if (_whitelistedTokens[_withdrawal.symbol] == address(0))
            revert UnsupportedToken(_withdrawal.symbol);
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

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
