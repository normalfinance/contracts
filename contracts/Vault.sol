// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

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

contract Vault is Initializable, AccessControlUpgradeable, IWormholeReceiver {
    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant FEE_CONTROLLER_ROLE =
        keccak256("FEE_CONTROLLER_ROLE");

    uint256 public fee;

    IWormholeRelayer public immutable wormholeRelayer;

    event Received(address, uint256);
    event WithdrawRequestReceived(address, uint);
    event Withdrawal(uint256, address);

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _wormholeRelayer, uint256 _fee) {
        _disableInitializers();

        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        fee = _fee;
    }

    function initialize() public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FEE_CONTROLLER_ROLE, msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    receive() external payable {
        emit Received(msg.sender, msg.value);

        // TODO: can we get feeController address from FEE_CONTROLLER_ROLE?
        // feeController.transfer(msg.value * fee);
    }

    function adjustFee(uint256 _newFee) external onlyRole(FEE_CONTROLLER_ROLE) {
        fee = _newFee;
    }

    // function withdrawFees(
    //     uint256 _amount
    // ) external onlyRole(FEE_CONTROLLER_ROLE) {
    //     require(
    //         address(this).balance >= _amount,
    //         "Cannot withdraw more than the amount in the contract."
    //     );
    //     feeController.transfer(_amount);
    // }

    function changeFeeController(
        address payable _newFeeController
    ) external onlyRole(FEE_CONTROLLER_ROLE) {
        require(_newFeeController != address(0), "Invalid _newFeeController");
        // feeController = _newFeeController;
    }

    /**
     * @notice Endpoint that the Wormhole Relayer contract will call
     * to deliver the greeting
     */
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory, // additionalVaas
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 // deliveryHash
    ) public payable override {
        require(msg.sender == address(wormholeRelayer), "Only relayer allowed");

        (uint256 amount, address payable destination) = abi.decode(
            payload,
            (uint256, address)
        );

        // emit WithdrawRequestReceived(
        //     latestGreeting,
        //     sourceChain,
        //     fromWormholeFormat(sourceAddress)
        // );

        destination.transfer(amount);

        emit Withdrawal(amount, destination);
    }

    /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/
}
