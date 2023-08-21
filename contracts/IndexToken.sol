// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// Interfaces
import "./interfaces/IIndexToken.sol";

// Lib
import "./lib/SharedStructs.sol";

// Modules
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {Blacklistable} from "./Blacklistable.sol";

import "../lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol";

//  /$$   /$$                                             /$$
// | $$$ | $$                                            | $$
// | $$$$| $$  /$$$$$$   /$$$$$$  /$$$$$$/$$$$   /$$$$$$ | $$
// | $$ $$ $$ /$$__  $$ /$$__  $$| $$_  $$_  $$ |____  $$| $$
// | $$  $$$$| $$  \ $$| $$  \__/| $$ \ $$ \ $$  /$$$$$$$| $$
// | $$\  $$$| $$  | $$| $$      | $$ | $$ | $$ /$$__  $$| $$
// | $$ \  $$|  $$$$$$/| $$      | $$ | $$ | $$|  $$$$$$$| $$
// |__/  \__/ \______/ |__/      |__/ |__/ |__/ \_______/|__/

contract IndexToken is
    IIndexToken,
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ERC20PermitUpgradeable,
    UUPSUpgradeable,
    Blacklistable
{
    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    address public masterMinter;

    mapping(address => bool) internal minters;
    mapping(address => uint256) internal minterAllowed;

    mapping(address => uint256) private ownerships;

    uint256 constant GAS_LIMIT = 50_000;
    IWormholeRelayer public immutable wormholeRelayer;

    event MinterConfigured(address indexed minter, uint256 minterAllowedAmount);
    event MinterRemoved(address indexed oldMinter);
    event MasterMinterChanged(address indexed newMasterMinter);

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        address newMasterMinter,
        address _wormholeRelayer
    ) public initializer {
        require(
            newMasterMinter != address(0),
            "IndexToken: new masterMinter is the zero address"
        );

        __ERC20_init(tokenName, tokenSymbol);
        __ERC20Burnable_init();
        __Pausable_init();
        __Ownable_init();
        __ERC20Permit_init(tokenName);
        __UUPSUpgradeable_init();

        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
    }

    /**
     * @dev Throws if called by any account other than a minter
     */
    modifier onlyMinters() {
        require(minters[msg.sender], "IndexToken: caller is not a minter");
        _;
    }

    /**
     * @dev Throws if called by any account other than the masterMinter
     */
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

    /**
     * @dev Get minter allowance for an account
     * @param minter The address of the minter
     */
    function minterAllowance(address minter) external view returns (uint256) {
        return minterAllowed[minter];
    }

    /**
     * @dev Checks if account is a minter
     * @param account The address to check
     */
    function isMinter(address account) external view returns (bool) {
        return minters[account];
    }

    /// @notice Returns the _account balance.
    /// @param _account Desired _account
    function getOwnership(
        address _account
    ) public view virtual returns (uint256) {
        return ownerships[_account];
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Function to mint tokens
     * @param _to The address that will receive the minted tokens.
     * @param _amount The amount of tokens to mint. Must be less than or equal
     * to the minterAllowance of the caller.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(
        address _to,
        uint256 _amount
    )
        external
        whenNotPaused
        onlyMinters
        notBlacklisted(msg.sender)
        notBlacklisted(_to)
        returns (bool)
    {
        require(_to != address(0), "IndexToken: mint to the zero address");
        require(_amount > 0, "IndexToken: mint amount not greater than 0");

        uint256 mintingAllowedAmount = minterAllowed[msg.sender];
        require(
            _amount <= mintingAllowedAmount,
            "IndexToken: mint amount exceeds minterAllowance"
        );

        _mint(_to, _amount);

        minterAllowed[msg.sender] = mintingAllowedAmount.sub(_amount);

        return true;
    }

    function burnAndWithdraw(
        uint16 targetChain,
        address targetAddress,
        SharedStructs.WithdrawRequest calldata _withdrawal,
        bytes32 _hash,
        bytes calldata _signature,
        uint16 refundChain,
        address refundAddress
    ) external whenNotPaused onlyMinters notBlacklisted(msg.sender) {
        if (
            SignatureChecker.isValidSignatureNow(
                _withdrawal.owner,
                _hash,
                _signature
            ) == false
        ) revert InvalidSignature();

        // Ensure enough gas for Wormhole
        uint256 cost = quoteCrossChainGreeting(targetChain);
        require(msg.value == cost);

        // Burn tokens
        _burn(_withdrawal.owner, 100);

        // Update ownership
        _updateOwnership(msg.sender, 100);

        // Trigger withdrawal in the correct Vault
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain,
            targetAddress,
            abi.encode(_withdrawal, _hash, _signature), // payload
            0, // no receiver value needed since we're just passing a message
            GAS_LIMIT,
            refundChain,
            refundAddress
        );
    }

    /**
     * @notice Returns the cost (in wei) of a greeting
     */
    function quoteCrossChainGreeting(
        uint16 targetChain
    ) public view returns (uint256 cost) {
        (cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0,
            GAS_LIMIT
        );
    }

    /**
     * @dev Function to add/update a new minter
     * @param minter The address of the minter
     * @param minterAllowedAmount The minting amount allowed for the minter
     * @return True if the operation was successful.
     */
    function configureMinter(
        address minter,
        uint256 minterAllowedAmount
    ) external whenNotPaused onlyMasterMinter returns (bool) {
        minters[minter] = true;
        minterAllowed[minter] = minterAllowedAmount;
        emit MinterConfigured(minter, minterAllowedAmount);
        return true;
    }

    /**
     * @dev Function to remove a minter
     * @param minter The address of the minter to remove
     * @return True if the operation was successful.
     */
    function removeMinter(
        address minter
    ) external onlyMasterMinter returns (bool) {
        minters[minter] = false;
        minterAllowed[minter] = 0;
        emit MinterRemoved(minter);
        return true;
    }

    function updateMasterMinter(address _newMasterMinter) external onlyOwner {
        require(
            _newMasterMinter != address(0),
            "FiatToken: new masterMinter is the zero address"
        );
        masterMinter = _newMasterMinter;
        emit MasterMinterChanged(masterMinter);
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the balance of many accounts
    /// @dev
    /// @param _account Address to update
    /// @param _newOwnership Updated balance
    function _updateOwnership(
        address _account,
        uint256 _newOwnership
    ) internal {
        ownerships[_account] += _newOwnership;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
