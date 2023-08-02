// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Interfaces
import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVault.sol";

// Upgradeable Modules
import "../node_modules/@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";

// Modules
import "../node_modules/@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

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
contract Proxy is Initializable, OwnableUpgradeable {
    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    address public indexTokenAddress;
    IVault private vault;

    mapping(address => uint256) public balances;

    struct WithdrawRequest {
        address owner;
        bytes32 symbol;
        uint256 amount;
        address payable to;
    }

    event TokenBurn(address, uint256);

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param _indexTokenAddress a parameter just like in doxygen (must be followed by parameter name)
    function initialize(
        address _indexTokenAddress,
        IVault _vaultAddress
    ) public initializer {
        __Ownable_init();

        indexTokenAddress = _indexTokenAddress;
        vault = _vaultAddress;
    }

    modifier onlyBalance(uint256 _amount) {
        require(
            balances[msg.sender] >= _amount,
            "Cannot spend more than balance"
        );
        _;
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the _account balance.
    function getVault() public view virtual returns (IVault) {
        return vault;
    }

    /// @notice Returns the _account balance.
    function getTotalBalance() public view virtual returns (uint256) {
        return IERC20(indexTokenAddress).balanceOf(address(this));
    }

    /// @notice Returns the _account balance.
    /// @param _account Desired _account
    function getBalance(
        address _account
    ) public view virtual returns (uint256) {
        return balances[_account];
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice
    /// @dev
    /// @param _accounts List of accounts to update allowances
    /// @param _investments List of allowances to update
    function updateBalances(
        address[] calldata _accounts,
        uint256[] calldata _investments
    ) external onlyOwner {
        require(
            _accounts.length == _investments.length,
            "Invalid array parameter lengths"
        );

        for (uint256 i = 0; i < _accounts.length; ++i) {
            balances[_accounts[i]] += _investments[i];
        }
    }

    /// @notice
    /// @dev
    /// @param _withdrawals ...
    /// @param _toBurn ...
    /// @param _hash ...
    /// @param _signature ...
    function batchWithdraw(
        WithdrawRequest[] calldata _withdrawals,
        uint256[] calldata _toBurn,
        bytes32[] calldata _hash,
        bytes[] calldata _signature
    ) external onlyOwner {
        require(
            _withdrawals.length == _toBurn.length &&
                _withdrawals.length == _hash.length &&
                _withdrawals.length == _signature.length,
            "Invalid address arrays"
        );

        for (uint256 i = 0; i < _withdrawals.length; ++i) {
            // validate signature
            if (
                SignatureChecker.isValidSignatureNow(
                    _withdrawals[i].owner,
                    _hash[i],
                    _signature[i]
                )
            ) {
                // call withdraw from Vault contract
                getVault().withdraw(
                    _withdrawals[i],
                    _toBurn[i],
                    _hash[i],
                    _signature[i]
                );

                // update msg.sender allowance
                balances[_withdrawals[i].owner] -= _toBurn[i];

                // burn index tokens
                ERC20BurnableUpgradeable(indexTokenAddress).burnFrom(
                    _withdrawals[i].owner,
                    _toBurn[i]
                );
                emit TokenBurn(_withdrawals[i].owner, _toBurn[i]);
            }
        }
    }
}
