// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Modules
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

//  /$$   /$$                                             /$$
// | $$$ | $$                                            | $$
// | $$$$| $$  /$$$$$$   /$$$$$$  /$$$$$$/$$$$   /$$$$$$ | $$
// | $$ $$ $$ /$$__  $$ /$$__  $$| $$_  $$_  $$ |____  $$| $$
// | $$  $$$$| $$  \ $$| $$  \__/| $$ \ $$ \ $$  /$$$$$$$| $$
// | $$\  $$$| $$  | $$| $$      | $$ | $$ | $$ /$$__  $$| $$
// | $$ \  $$|  $$$$$$/| $$      | $$ | $$ | $$|  $$$$$$$| $$
// |__/  \__/ \______/ |__/      |__/ |__/ |__/ \_______/|__/

/// @title IndexToken contract
/// @author Joshua Blew <joshua@normalfinance.io>
/// @notice ERC-20 token representing ownership in a Vault
contract IndexToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ERC20PermitUpgradeable,
    UUPSUpgradeable
{
    using SafeMath for uint256;

    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    address public masterMinter;

    mapping(address => bool) internal _minters;
    mapping(address => uint256) internal _minterAllowed;

    mapping(bytes => bool) public seenWithdrawalSignatures;

    event MinterConfigured(address indexed minter, uint256 minterAllowedAmount);
    event MinterRemoved(address indexed oldMinter);
    event MasterMinterChanged(address indexed newMasterMinter);

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract after deployment
    /// @dev Replaces the constructor() to support upgradeability (https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable)
    /// @param _tokenName The name of the token
    /// @param _tokenSymbol The tokens symbol
    /// @param _newMasterMinter An address to configure all minters
    function initialize(
        string memory _tokenName,
        string memory _tokenSymbol,
        address _newMasterMinter
    ) public initializer {
        require(
            _newMasterMinter != address(0),
            "IndexToken: new masterMinter is the zero address"
        );

        __ERC20_init(_tokenName, _tokenSymbol);
        __ERC20Burnable_init();
        __Pausable_init();
        __Ownable_init();
        __ERC20Permit_init(_tokenName);
        __UUPSUpgradeable_init();

        masterMinter = _newMasterMinter;
    }

    /// @notice Throws if called by any account other than a minter
    modifier onlyMinters() {
        require(_minters[msg.sender], "IndexToken: caller is not a minter");
        _;
    }

    /// @notice Throws if called by any account other than the masterMinter
    modifier onlyMasterMinter() {
        require(
            msg.sender == masterMinter,
            "IndexToken: caller is not the masterMinter"
        );
        _;
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Get minter allowance for an account
    /// @param _minter The address of the minter
    function minterAllowance(address _minter) external view returns (uint256) {
        return _minterAllowed[_minter];
    }

    /// @notice Checks if account is a minter
    /// @param _account The address to check
    function isMinter(address _account) external view returns (bool) {
        return _minters[_account];
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses `whenNotPaused` functions for emergencies
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpauses `whenNotPaused` functions
    function unpause() public onlyOwner {
        _unpause();
    }

    /// @notice Function to mint tokens
    /// @dev Mint tokens then update minter allowance
    /// @param _to The address that will receive the minted tokens
    /// @param _amount The amount of tokens to mint. Must be less than or equal to the minterAllowance of the caller.
    /// @return A boolean that indicates if the operation was successful
    function mint(
        address _to,
        uint256 _amount
    ) external whenNotPaused onlyMinters returns (bool) {
        uint256 mintingAllowedAmount = _minterAllowed[msg.sender];
        require(
            _amount <= mintingAllowedAmount,
            "IndexToken: mint amount exceeds minterAllowance"
        );

        _mint(_to, _amount);

        unchecked {
            _minterAllowed[msg.sender] = mintingAllowedAmount.sub(_amount);
        }

        return true;
    }

    /// @notice Function to burn tokens
    /// @dev Burn tokens and accepts withdrawal args as unnamed params
    /// @dev for passage to Vault withdraw execution via
    /// @dev Ethers interface.parseTransaction()
    /// @param _amount Number of tokens to burn
    function burnForWithdrawal(
        uint256 _amount,
        uint16, // Chain of withdrawal token
        address, // Address of withdrawal token (address(0) for native)
        address payable, // Address of withdrawal destination,
        bytes32, // Message hash of withdrawal args with format: YYYY-MM-DD:fundId:assetSymbol:usdValue:destination (i.e. 2023-09-18:NCI:ETH:100:0x9a9C45349227f8c7Cbe52680eCa15597db135858)
        bytes calldata // Owner signature of message hash^ used to authorize Vault withdrawal
    ) external whenNotPaused onlyMasterMinter {
        burn(_amount);
    }

    /// @notice Function to add/update a new minter
    /// @param _minter The address of the minter
    /// @param _minterAllowedAmount The minting amount allowed for the minter
    /// @return True if the operation was successful
    function configureMinter(
        address _minter,
        uint256 _minterAllowedAmount
    ) external whenNotPaused onlyMasterMinter returns (bool) {
        _minters[_minter] = true;
        _minterAllowed[_minter] = _minterAllowedAmount;
        emit MinterConfigured(_minter, _minterAllowedAmount);
        return true;
    }

    /// @notice Function to remove a minter
    /// @param _minter The address of the minter to remove
    /// @return True if the operation was successful
    function removeMinter(
        address _minter
    ) external onlyMasterMinter returns (bool) {
        _minters[_minter] = false;
        _minterAllowed[_minter] = 0;
        emit MinterRemoved(_minter);
        return true;
    }

    /// @notice Function update the master minter
    /// @param _newMasterMinter The address of a new master minter
    function updateMasterMinter(address _newMasterMinter) external onlyOwner {
        require(
            _newMasterMinter != address(0),
            "IndexToken: new masterMinter is the zero address"
        );
        masterMinter = _newMasterMinter;
        emit MasterMinterChanged(masterMinter);
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(_from, _to, _amount);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
