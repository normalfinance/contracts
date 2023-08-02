// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Interfaces
import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Modules
import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

// Upgradeable Modules
import "../node_modules/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
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
    using ECDSA for bytes32;

    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    uint256 constant TEN_THOUSAND = 10000;
    uint256 constant ONE_YEAR = 31556952;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FEE_CONTROLLER_ROLE =
        keccak256("FEE_CONTROLLER_ROLE");

    address payable private feeController;

    uint256 private annualFee; // bps
    mapping(bytes32 => uint256) private lastFeeWithdrawalDates;

    address internal indexToken;
    mapping(bytes32 => address) internal whitelistedTokens;
    mapping(bytes32 => uint256) internal tokenFeesToCollect;

    struct WithdrawRequest {
        address owner;
        bytes32 symbol;
        uint256 amount;
        address payable to;
    }

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
        uint256 _annualFee,
        bytes32[] memory _tokenSymbols,
        address[] memory _tokenAddresses
    ) public initializer {
        require(0 < _annualFee && _annualFee <= 5000, "Invalid annual fee"); // b/t 0% and 5%
        require(
            _tokenSymbols.length == _tokenAddresses.length,
            "Invalid address arrays"
        );

        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, _pauser);
        _grantRole(FEE_CONTROLLER_ROLE, _feeController);

        feeController = _feeController;

        annualFee = _annualFee;

        indexToken = _indexTokenAddress;

        for (uint256 i = 0; i < _tokenSymbols.length; ++i) {
            whitelistedTokens[_tokenSymbols[i]] = _tokenAddresses[i];
            tokenFeesToCollect[_tokenSymbols[i]] = 0;
            lastFeeWithdrawalDates[_tokenSymbols[i]] = getOneMonthAgo();
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
        return annualFee;
    }

    /// @notice Returns the timestamp when the last fee was collected.
    /// @param _symbol Desired token last fee withdrawal date
    function getLastFeeWithdrawalDate(
        bytes32 _symbol
    ) public view virtual returns (uint) {
        return lastFeeWithdrawalDates[_symbol];
    }

    /// @notice Returns the outstanding fees to collect for a token.
    /// @param _symbol Desired token fees to collect
    function getTokenFeesToCollect(
        bytes32 _symbol
    ) public view virtual returns (uint) {
        return tokenFeesToCollect[_symbol];
    }

    /// @notice Returns the token contract address.
    /// @param _symbol Desired token contract address
    function getWhitelistedToken(
        bytes32 _symbol
    ) public view virtual returns (address) {
        return whitelistedTokens[_symbol];
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
        require(whitelistedTokens[_symbol] != address(0), "Unsupported symbol");
        require(_amount > 0, "Amount must be greater than zero");

        IERC20(whitelistedTokens[_symbol]).transferFrom(
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
        WithdrawRequest calldata _withdrawal,
        uint256 _toBurn,
        bytes32 _hash,
        bytes calldata _signature
    ) external payable onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(
            whitelistedTokens[_withdrawal.symbol] != address(0),
            "Unsupported symbol"
        );
        require(_withdrawal.amount > 0, "Amount must be greater than zero");
        require(
            _withdrawal.amount <=
                IERC20(whitelistedTokens[_withdrawal.symbol]).balanceOf(
                    address(this)
                ) -
                    tokenFeesToCollect[_withdrawal.symbol],
            "Insufficient Vault funds"
        );
        require(_withdrawal.to != address(0), "Invalid destination address");
        require(
            0 < _toBurn &&
                _toBurn <= IERC20(indexToken).balanceOf(_withdrawal.owner),
            "Invalid index tokens to burn"
        );
        require(
            SignatureChecker.isValidSignatureNow(
                _withdrawal.owner,
                _hash,
                _signature
            ) == true,
            "Invalid signature"
        );

        // Calculate and track fee
        uint256 timeDelta = block.timestamp -
            lastFeeWithdrawalDates[_withdrawal.symbol];
        uint256 proratedFee = (((annualFee * _withdrawal.amount) * timeDelta) /
            ONE_YEAR /
            TEN_THOUSAND);

        tokenFeesToCollect[_withdrawal.symbol] += proratedFee;

        // Send token to destination
        IERC20(whitelistedTokens[_withdrawal.symbol]).transfer(
            _withdrawal.to,
            _withdrawal.amount - proratedFee
        );
        emit Withdrawal(
            _withdrawal.owner,
            _withdrawal.symbol,
            _withdrawal.amount,
            proratedFee
        );

        // Burn Index Token
        // ERC20BurnableUpgradeable(indexToken).burnFrom(_withdrawal.owner, _toBurn);
        // emit TokenBurn(_withdrawal.owner, _toBurn);
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
        require(_tokenAddress != address(0), "Invalid token address");

        whitelistedTokens[_symbol] = _tokenAddress;
        tokenFeesToCollect[_symbol] = 0;
        lastFeeWithdrawalDates[_symbol] = getOneMonthAgo();

        emit Whitelist(_symbol);
    }

    /// @notice Updates Vault annual fee
    /// @dev
    /// @param _newAnnualFee Updated annual basis points fee
    function adjustFee(
        uint256 _newAnnualFee
    ) external onlyRole(FEE_CONTROLLER_ROLE) {
        require(
            0 < _newAnnualFee && _newAnnualFee <= 5000,
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

        for (uint256 i = 0; i < _symbols.length; ++i) {
            if (whitelistedTokens[_symbols[i]] != address(0)) {
                uint256 vaultBalance = IERC20(whitelistedTokens[_symbols[i]])
                    .balanceOf(address(this));

                if (vaultBalance > 0) {
                    uint256 timeDelta = block.timestamp -
                        lastFeeWithdrawalDates[_symbols[i]];

                    uint256 tokenFee = (((annualFee * vaultBalance) *
                        timeDelta) /
                        ONE_YEAR /
                        TEN_THOUSAND);

                    IERC20(whitelistedTokens[_symbols[i]]).transfer(
                        feeController,
                        tokenFee + tokenFeesToCollect[_symbols[i]]
                    );

                    emit FeeCollection(_now, totalFee);

                    totalFee += tokenFee;

                    tokenFeesToCollect[_symbols[i]] = 0;

                    lastFeeWithdrawalDates[_symbols[i]] = _now;
                }
            }
        }
    }
}
