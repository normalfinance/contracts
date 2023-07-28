// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../node_modules/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../node_modules/@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

//  /$$   /$$                                             /$$
// | $$$ | $$                                            | $$
// | $$$$| $$  /$$$$$$   /$$$$$$  /$$$$$$/$$$$   /$$$$$$ | $$
// | $$ $$ $$ /$$__  $$ /$$__  $$| $$_  $$_  $$ |____  $$| $$
// | $$  $$$$| $$  \ $$| $$  \__/| $$ \ $$ \ $$  /$$$$$$$| $$
// | $$\  $$$| $$  | $$| $$      | $$ | $$ | $$ /$$__  $$| $$
// | $$ \  $$|  $$$$$$/| $$      | $$ | $$ | $$|  $$$$$$$| $$
// |__/  \__/ \______/ |__/      |__/ |__/ |__/ \_______/|__/

/// @title A title that should describe the contract/interface
/// @author Joshua Blew <joshua@normalfinance.io>
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details
contract Vault is Initializable, PausableUpgradeable, AccessControlUpgradeable {
    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FEE_CONTROLLER_ROLE =
        keccak256("FEE_CONTROLLER_ROLE");

    address private immutable feeController;

    address normalToken;

    uint256 public annualFee; // bps
    uint public lastFeeWithdrawDate;

    AggregatorV3Interface internal normDataFeed;
    AggregatorV3Interface internal ethDataFeed;

    event Deposit(address);
    event Withdrawal(address, address, uint256, uint256);
    event FeeCollection(uint, uint256);
    event TokenMint(address, uint256);
    event TokenBurn(address, uint256);

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _normalToken,
        uint256 _annualFee,
        address _normChainlinkContract,
        address _ethChainlinkContract
    ) {
        require(_annualFee > 0 && _annualFee <= 10000, "Invalid annual fee");
        _disableInitializers();

        normalToken = _normalToken;
        annualFee = _annualFee;
        normDataFeed = AggregatorV3Interface(_normChainlinkContract);
        ethDataFeed = AggregatorV3Interface(_ethChainlinkContract);
    }

    function initialize(address _feeController) public initializer {
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(FEE_CONTROLLER_ROLE, _feeController);

        feeController = _feeController;
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param
    function deposit() external payable whenNotPaused {
        require(msg.value > 0, "You need to send some ether");

        // receive tokens
        // ...
        emit Deposit(msg.sender);

        // mint $NORM
        (, int256 normPrice, , , ) = normDataFeed.latestRoundData();
        (, int256 ethPrice, , , ) = ethDataFeed.latestRoundData();
        uint256 depositValue = msg.value * ethPrice;
        uint256 numTokensToMint = depositValue / normPrice;
        normalToken.mint(msg.sender, numTokensToMint);
        emit TokenMint(msg.sender, numTokensToMint);
    }

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param _token
    /// @param _amount
    /// @param _destination
    function withdraw(
        address _token,
        uint256 _amount,
        address _destination
    ) external payable whenNotPaused {
        require(_token != address(0), "Invalid token address");
        require(_amount > 0, "Amount must be greater than zero");
        require(_destination != address(0), "Invalid destination address");
        require(_amount <= address(this).balance, "Insufficient Vault funds");

        // Ensure msg.sender has positive $NORM balance
        uint256 balance = IERC20(_token).balanceOf(msg.sender);
        require(
            balance > 0,
            "Redemption token balance must be greater than zero"
        );
        require(balance >= _amount, "Insufficient funds");

        // Compare msg.sender $NORM holdings vs. withdrawal
        (, int256 normPrice, , , ) = normDataFeed.latestRoundData();
        uint256 currentValue = uint(normPrice) * balance;
        require(currentValue >= value, "Insufficient funds");

        // Collect fee
        uint daysDiff = (now - lastFeeWithdrawDate) / 60 / 60 / 24;
        uint256 proratedFee = ((annualFee / 365) * daysDiff) / 10000; // TODO: change to wei?
        feeController.transfer(_amount * proratedFee);

        // Send token to destination
        _destination.transfer(_amount * (1 - proratedFee)); // TODO: change to wei?
        emit Withdrawal(msg.sender, _token, _amount, proratedFee);

        // Burn $NORM tokens
        normalToken.burnFrom(msg.sender, _amount);
        emit TokenBurn(msg.sender, _amount);
    }

    /*///////////////////////////////////////////////////////////////
                        Admin functions
    //////////////////////////////////////////////////////////////*/

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function adjustFee(
        uint256 _newAnnualFee
    ) external onlyRole(FEE_CONTROLLER_ROLE) {
        require(
            _newAnnualFee > 0 && _newAnnualFee <= 10000,
            "Invalid annual fee"
        );
        annualFee = _newAnnualFee;
    }

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @return totalFee
    function withdrawFee()
        external
        onlyRole(FEE_CONTROLLER_ROLE)
        returns (uint256 totalFee)
    {
        uint daysDiff = (now - lastFeeWithdrawDate) / 60 / 60 / 24;
        require(daysDiff <= 28, "Cannot withdraw fee more than once a month");

        totalFee = address(this).balance * (annualFee / 12);
        feeController.transfer(totalFee);

        emit FeeCollection(now, totalFee);

        lastFeeWithdrawDate = now;
    }
}
