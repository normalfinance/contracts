// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../node_modules/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../node_modules/@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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

contract Registry is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    AggregatorV3Interface internal ethDataFeed;

    address private immutable evmVault;
    address private immutable solanaVault;
    address private immutable tokenContract;

    uint256 constant GAS_LIMIT = 50_000;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IWormholeRelayer public immutable wormholeRelayer;

    struct InvestmentInfo {
        uint256 quantity;
        uint256 value;
    }

    // owner > keccak(ASSET_SYMBOL) > usdValue
    mapping(address => mapping(bytes32 => InvestmentInfo)) public investments;

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    event NewRecord(address, uint256);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _evmVault,
        address _solanaVault,
        address _wormholeRelayer,
        address ethContract
    ) {
        _disableInitializers();
        evmVault = _evmVault;
        solanaVault = _solanaVault;
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        ethDataFeed = AggregatorV3Interface(ethContract);
    }

    function initialize() public initializer {
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    function getInvestment(
        string calldata asset
    ) public view virtual returns (InvestmentInfo memory) {
        return investments[msg.sender][keccak256(abi.encode(asset))];
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
    Record investment
    Mint tokens */
    function record(
        address _owner,
        string calldata _asset,
        uint256 _quantity,
        uint256 _value
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_owner != address(0), "Invalid owner");
        require(_value != 0, "value must be positive");

        InvestmentInfo storage investment = investments[_owner][
            keccak256(abi.encode(_asset))
        ];

        investments[_owner][keccak256(abi.encode(_asset))] = InvestmentInfo(
            investment.quantity + _quantity,
            investment.value + _value
        );

        emit NewRecord(_owner, _value);
    }

    /**
     *
     */
    function withdraw(
        uint16 targetChain,
        address targetAddress,
        string calldata asset,
        uint256 value,
        address destination
    ) external payable {
        require(targetAddress != address(0), "Invalid targetAddress");
        require(value != 0, "value must be positive");
        require(destination != address(0), "Invalid destination");

        uint256 balance = IERC20(tokenContract).balanceOf(msg.sender);

        (, int256 normPrice, , , ) = ethDataFeed.latestRoundData();

        uint256 currentValue = uint(normPrice) * balance;
        require(currentValue >= value, "Insufficient funds");

        // fetch price of target token
        (, int256 ethPrice, , , ) = ethDataFeed.latestRoundData();

        // ensure value of investment in >= withdraw request
        uint256 assetValue = uint(ethPrice) *
            investments[msg.sender][keccak256(abi.encode(asset))].value;
        require(assetValue >= value, "Insufficient funds");

        // send wormhole message to withdraw x target tokens to destination
        uint256 cost = quoteCrossChainWithdrawal(targetChain);
        require(msg.value == cost);
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain,
            targetAddress,
            abi.encode(quantity, destination), // payload
            0, // no receiver value needed since we're just passing a message
            GAS_LIMIT
        );

        // if there is a delta, fetch price of backup token
        // (, int256 ethUsdPrice, , , ) = ethUsdDataFeed.latestRoundData();

        // send wormhole message to backup token Vault to withdraw remaining value
        // uint256 cost = quoteCrossChainWithdrawal(targetChain);
        // require(msg.value == cost);
        // wormholeRelayer.sendPayloadToEvm{value: cost}(
        //     targetChain,
        //     targetAddress,
        //     abi.encode(amount, destination), // payload
        //     0, // no receiver value needed since we're just passing a message
        //     GAS_LIMIT
        // );
    }

    /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the cost (in wei) of a greeting
     */
    function quoteCrossChainWithdrawal(
        uint16 targetChain
    ) private view returns (uint256 cost) {
        (cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0,
            GAS_LIMIT
        );
    }
}
