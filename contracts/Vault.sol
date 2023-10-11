// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Modules
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
error InvalidFee(uint256);

/// @title Vault contract
/// @author Joshua Blew <joshua@normalfinance.io>
/// @notice Holds deposits for crypto funds and enables authorized withdrawals
contract Vault is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    /// @notice The annual basis points collected on all deposits
    uint256 private _fee;

    /// @notice The timestamp when the _fee was last collected
    uint private _lastFeeCollection;

    /// @notice Prorated fees from withdrawals awaiting collection
    mapping(address => uint256) private _feesByToken;

    /// @notice Record of processed withdrawals to avoid duplicates
    mapping(bytes => bool) private _seenWithdrawalSignatures;

    /// @notice The maximum the fee can be set
    uint256 private immutable FEE_LIMIT = 5_000;

    event Withdrawal(address indexed owner, uint256 amount);
    event TokenWithdrawal(address indexed owner, address token, uint256 amount);

    event FeeCollection(uint timestamp, uint256 fee);
    event TokenFeeCollection(uint timestamp, address token, uint256 fee);

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    // solhint-disable-next-line no-empty-blocks
    receive() external payable virtual {}

    /// @notice Initializes the contract after deployment
    /// @dev Replaces the constructor() to support upgradeability
    /// (https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable)
    /// @param _aFee The basis points fee applied to all deposits
    function initialize(uint256 _aFee) public initializer isValidFee(_aFee) {
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        _fee = _aFee;
        _lastFeeCollection = block.timestamp;
    }

    modifier isValidFee(uint256 aFee) {
        if (aFee > FEE_LIMIT) revert InvalidFee(aFee);
        _;
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the fee
    function getFee() public view virtual returns (uint256) {
        return _fee;
    }

    /// @notice Returns the prorated fee for a withdrawal
    /// @dev Uses the time since _lastFeeCollection to calculate annualized fee
    /// @param _amount Withdrawal amount
    function getProratedFee(
        uint256 _amount
    ) internal view returns (uint256 proratedFee) {
        uint256 timeDelta = block.timestamp - _lastFeeCollection;

        proratedFee = (_fee * _amount * timeDelta) / 31_556_952 / 10_000;
    }

    /// @notice Returns the timestamp when the last fee was collected
    function getLastFeeCollection() public view virtual returns (uint) {
        return _lastFeeCollection;
    }

    /// @notice Returns the prorated withdrawal fees ready to collect
    /// @param _token Token address
    function getTokenFeesToCollect(
        address _token
    ) public view virtual returns (uint256) {
        return _feesByToken[_token];
    }

    /// @notice Returns true if withdrawl signature has been processed
    /// @param _signature Signature to check
    function checkWithdrawalSignature(
        bytes calldata _signature
    ) public view virtual returns (bool) {
        return _seenWithdrawalSignatures[_signature];
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Function to withdraw the native token (i.e. ETH)
    /// @param _owner Address of investor
    /// @param _amount Native token amount
    /// @param _to Address of withdrawal destination
    /// @param _hash Message hash of withdrawal args with format: YYYY-MM-DD:fundId:assetSymbol:usdValue:destination (i.e. 2023-09-18:NCI:ETH:100:0x9a9C45349227f8c7Cbe52680eCa15597db135858)
    /// @param _signature Owner signature of message hash^ used to authorize Vault withdrawal
    function withdraw(
        address _owner,
        uint256 _amount,
        address payable _to,
        bytes32 _hash,
        bytes calldata _signature
    ) external onlyOwner {
        if (!SignatureChecker.isValidSignatureNow(_owner, _hash, _signature))
            revert InvalidSignature();

        require(
            !_seenWithdrawalSignatures[_signature],
            "Vault: Withdrawal already processed"
        );
        _seenWithdrawalSignatures[_signature] = true;

        _withdraw(_owner, _amount, _to);
    }

    /// @notice Function to withdraw non-native tokens (i.e. ERC20)
    /// @param _owner Address of investor
    /// @param _token Token address
    /// @param _to Address of withdrawal destination
    /// @param _hash Message hash of withdrawal args with format: YYYY-MM-DD:fundId:assetSymbol:usdValue:destination (i.e. 2023-09-18:NCI:ETH:100:0x9a9C45349227f8c7Cbe52680eCa15597db135858)
    /// @param _signature Owner signature of message hash^ used to authorize Vault withdrawal
    function withdrawToken(
        address _owner,
        address _token,
        uint256 _amount,
        address payable _to,
        bytes32 _hash,
        bytes memory _signature
    ) external onlyOwner {
        if (!SignatureChecker.isValidSignatureNow(_owner, _hash, _signature))
            revert InvalidSignature();

        require(
            !_seenWithdrawalSignatures[_signature],
            "Vault: Withdrawal already processed"
        );
        _seenWithdrawalSignatures[_signature] = true;

        _withdrawToken(_owner, _token, _amount, _to);
    }

    /// @notice Pauses `whenNotPaused` functions for emergencies
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpauses `whenNotPaused` functions
    function unpause() public onlyOwner {
        _unpause();
    }

    /// @notice Function to update the fee
    /// @param _newFee Updated fee
    function adjustFee(uint256 _newFee) external onlyOwner isValidFee(_newFee) {
        _fee = _newFee;
    }

    /// @notice Function to collect native token fees
    /// @param _to Address to send fees to
    function collectFees(address payable _to) external onlyOwner {
        uint256 fee = getProratedFee(address(this).balance);
        uint256 totalFee = fee + _feesByToken[address(0)];

        _feesByToken[address(0)] = 0;
        _lastFeeCollection = block.timestamp;

        Address.sendValue(_to, totalFee);
        emit FeeCollection(block.timestamp, totalFee);
    }

    /// @notice Function to collect non-native token fees
    /// @param _to Address to send fees to
    /// @param _tokens Token addresses to collect fees for
    function collectTokenFees(
        address payable _to,
        address[] memory _tokens
    ) external onlyOwner {
        for (uint256 i = 0; i < _tokens.length; ) {
            uint256 tokenBalance = IERC20(_tokens[i]).balanceOf(address(this));

            uint256 fee = getProratedFee(tokenBalance);
            uint256 totalFee = fee + _feesByToken[_tokens[i]];

            _feesByToken[_tokens[i]] = 0;
            _lastFeeCollection = block.timestamp;

            SafeERC20.safeTransfer(IERC20(_tokens[i]), _to, totalFee);
            emit TokenFeeCollection(block.timestamp, _tokens[i], totalFee);

            unchecked {
                i += 1;
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    function _withdraw(
        address _owner,
        uint256 _amount,
        address payable _to
    ) internal {
        // Calculate prorated fee
        uint256 fee = getProratedFee(_amount);

        // Record fee for delayed collection
        _feesByToken[address(0)] += fee;

        // Send token to destination
        _to.transfer(_amount - fee);
        emit Withdrawal(_owner, _amount);
    }

    function _withdrawToken(
        address _owner,
        address _token,
        uint256 _amount,
        address payable _to
    ) internal {
        // Calculate prorated fee
        uint256 fee = getProratedFee(_amount);

        // Record fee for delayed collection
        _feesByToken[_token] += fee;

        // Send token to destination
        IERC20(_token).transfer(_to, _amount - fee);
        emit TokenWithdrawal(_owner, _token, _amount);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
