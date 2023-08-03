// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Interfaces
import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IProxy.sol";

// Lib
import "./lib/SharedStructs.sol";

// Upgradeable Modules
import "../node_modules/@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";

// Modules
import "../node_modules/@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

//  /$$   /$$                 s                            /$$
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
contract Proxy is IProxy, Initializable, OwnableUpgradeable {
    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    address private _tokenAddress;
    IVault private _vault;
    mapping(address => uint256) private _balances;

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param _aToken a parameter just like in doxygen (must be followed by parameter name)
    /// @param _aVault ...
    function initialize(address _aToken, IVault _aVault) public initializer {
        __Ownable_init();

        _tokenAddress = _aToken;
        _vault = _aVault;
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the _account balance.
    function getTokenBalance() public view virtual returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    /// @notice Returns the _account balance.
    /// @param _account Desired _account
    function getAccountBalance(
        address _account
    ) public view virtual returns (uint256) {
        return _balances[_account];
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the balance of many accounts
    /// @dev
    /// @param _accounts List of addresses to update
    /// @param _newBalances List of updated balances
    function updateBalances(
        address[] calldata _accounts,
        uint256[] calldata _newBalances
    ) external onlyOwner {
        if (_accounts.length != _newBalances.length) revert UnevenArrays();

        for (uint256 i = 0; i < _accounts.length; ++i) {
            _updateBalance(_accounts[i], _newBalances[i]);
        }
    }

    /// @notice
    /// @dev
    /// @param _withdrawals List of withdrawal requests
    /// @param _toBurn List of Index Tokens to burn for each withdrawal
    /// @param _hash List of withdrawal request hashs
    /// @param _signature List of withdrawal request signatures
    function batchWithdraw(
        SharedStructs.WithdrawRequest[] calldata _withdrawals,
        uint256[] calldata _toBurn,
        bytes32[] calldata _hash,
        bytes[] calldata _signature
    ) external onlyOwner {
        if (
            _withdrawals.length != _toBurn.length ||
            _withdrawals.length != _hash.length ||
            _withdrawals.length != _signature.length
        ) revert UnevenArrays();

        for (uint256 i = 0; i < _withdrawals.length; ++i) {
            _withdraw(_withdrawals[i], _toBurn[i], _hash[i], _signature[i]);
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the balance of many accounts
    /// @dev
    /// @param _account Address to update
    /// @param _newBalance Updated balance
    function _updateBalance(address _account, uint256 _newBalance) internal {
        _balances[_account] += _newBalance;
    }

    /// @notice
    /// @dev
    /// @param _withdrawal Withdrawal requests
    /// @param _toBurn Number of Index Tokens to burn
    /// @param _hash ...
    /// @param _signature ...
    function _withdraw(
        SharedStructs.WithdrawRequest calldata _withdrawal,
        uint256 _toBurn,
        bytes32 _hash,
        bytes calldata _signature
    ) internal {
        if (
            SignatureChecker.isValidSignatureNow(
                _withdrawal.owner,
                _hash,
                _signature
            ) == false
        ) revert InvalidSignature();

        // burn index tokens
        ERC20BurnableUpgradeable(_tokenAddress).burnFrom(
            _withdrawal.owner,
            _toBurn
        );
        emit TokenBurn(_withdrawal.owner, _toBurn);

        // update msg.sender allowance
        _balances[_withdrawal.owner] -= _toBurn;

        // calls withdraw from Vault contract and reverts if it fails
        (bool success, bytes memory result) = address(_vault).call(
            abi.encodePacked(
                _vault.withdraw.selector,
                abi.encode(_withdrawal, _toBurn, _hash, _signature)
            )
        );

        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
