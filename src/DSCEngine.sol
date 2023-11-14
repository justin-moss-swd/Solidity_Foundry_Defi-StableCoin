// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Justin Moss 2023
 *
 * @dev This is a contract made to be as minimal as possible.  It should maintain the tokens such that 1 token == $1 peg.
 * This is a stablecoin with the properties:
 * - Dollar Pegged
 * - Algorithmically Stable
 * - Exogenously Collateralized
 *
 * @dev It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * @dev The DSC system should always be "overcollaterized".
 * At no point should the value of all collateral <= the USD backed value of all DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic for minting and redeeming DSC, 
 * as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system.
 */
contract DSCEngine is ReentrancyGuard{
    // ==========================================
    // Errors
    // ==========================================

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();


    // ==========================================
    // Types
    // ==========================================

    using OracleLib for AggregatorV3Interface;


    // ==========================================
    // State Variables
    // ==========================================

    uint256 private constant _ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant _PRECISION = 1e18;
    uint256 private constant _LIQUIDATION_THRESHOLD = 50;
    uint256 private constant _LIQUIDATION_PRECISION = 100;
    uint256 private constant _LIQUIDATION_BONUS = 10;
    uint256 private constant _MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private _sPriceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private _sCollateralDeposited;
    mapping(address user => uint256 amount) private _sDSCMinted;

    address[] private _sCollateralTokens;

    DecentralizedStableCoin private immutable _iDsc;

    // ==========================================
    // Events
    // ==========================================

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);


    // ==========================================
    // Modifiers
    // ==========================================

    modifier moreThanZero(uint256 amount) {
        if(amount == 0) revert DSCEngine__NeedsMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if(_sPriceFeeds[token] == address(0)) revert DSCEngine__NotAllowedToken();
        _;
    }


    // ==========================================
    // Functions
    // ==========================================

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD Price Feed
        if(tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            _sPriceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            _sCollateralTokens.push(tokenAddresses[i]);
        }

        _iDsc = DecentralizedStableCoin(dscAddress);
    }

    
    // ==========================================
    // External Functions
    // ==========================================

    /** 
     * @param tokenCollateralAddress: The collateral address to redeem
     * @param amountCollateral: The amount of collateral to redeem
     * @param amountDscToBurn: The amount of DSC to burn
     * This function burns DSC and redeems underlying collateral in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    // If a user is almost undercollaterized, another user can be payed to liquidate

    /**
     * @param collateral: The ERC20 collateral address to liquidate from the user
     * @param user: The user who has broken the health factor.  Health factor should be below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to improve the users health factor
     *
     * @notice Liquidator can partially liquidate a user
     * @notice Liquidator will get a liquidation bonus for taking the users funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order to work
     * @notice A known bug would be if the protocol were 100% or less collateralized. Then the protocol wouldn't be able to incentivize the liquidators
     * For example, if the price of the collateral plummeted before anyone could be liquidated
     */
    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        
        // Check health factor if the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= _MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        // Burn user DSC "debt" and take collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * _LIQUIDATION_BONUS) / _LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeedCollateral(collateral, totalCollateralToRedeem, user, msg.sender);

        // Burn DSC
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getPrecision() external pure returns (uint256) {
        return _PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return _ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return _LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return _LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return _LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return _MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return _sCollateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(_iDsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return _sPriceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return _sCollateralDeposited[user][token];
    }


    // ==========================================
    // Public Functions
    // ==========================================

    function getTokenAmountFromUsd(address collateral, uint256 usdAmountInWei) public view returns (uint256) {
        // Price of ETH (token)
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_sPriceFeeds[collateral]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return ((usdAmountInWei * _PRECISION) / (uint256(price) * _ADDITIONAL_FEED_PRECISION));
    }

    // In order to redeem collateral:
    // Health factor must be over 1 AFTER collateral is pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) 
        public
        moreThanZero(amountCollateral)
        nonReentrant() 
    {
        _redeedCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
   
    /**
     * @param tokenCollateralAddress: The address of the token to deposit as collateral
     * @param amountCollateral: The amount of collateral to deposit
     * @param amountDscToMint: The amount of decentralized stablecoin to mint
     * @notice This function will deposit collater and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress, 
        uint256 amountCollateral, 
        uint256 amountDscToMint
    ) public {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress: The address of the token to deposit as collateral.
     * @param amountCollateral: The amount of collateral to deposit.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)   
        public 
        moreThanZero(amountCollateral) 
        isAllowedToken(tokenCollateralAddress)
        nonReentrant 
    {
        _sCollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        // Perform transfer
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        
        if(!success) revert DSCEngine__TransferFailed();
    }

    /**
     * @notice follows CEI
     * @notice Amount to mint must have more collateral value than the minimum threshold
     * @param amountDscToMint: The address of the token to withdraw as collateral
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        _sDSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = _iDsc.mint(msg.sender, amountDscToMint);
        if(!minted) revert DSCEngine__MintFailed();
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // might never hit
    }

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // Loop through each collateral token and get the amount the user has deposited, map to the price to get the USD value
        for(uint256 i = 0; i < _sCollateralTokens.length; i++) {
            address token = _sCollateralTokens[i];
            uint256 amount = _sCollateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }

        return totalCollateralValueInUsd;
    } 
    
    function getUsdValue(address token, uint256 amount /* in WEI */ ) public view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getAccountInformation(address user) external view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }


    // ==========================================
    // Internal Functions
    // ==========================================


    // * Check health factor
    // * Revert if the don't have enough
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);

        if(userHealthFactor < _MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreashold = (collateralValueInUsd * _LIQUIDATION_THRESHOLD) / _LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreashold * 1e18) / totalDscMinted;
    }
    
    
    // ==========================================
    // Private Functions
    // ==========================================

    /** 
     * @dev Low-level internal function.  Do not call unless the function it is checking for health factors being broken
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        _sDSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = _iDsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        
        // This condition is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        _iDsc.burn(amountDscToBurn);
    }

    function _redeedCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
        _sCollateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = _sDSCMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1 then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256){
        // Total DSC minted
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        // Total collaterall value
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * _LIQUIDATION_THRESHOLD) / _LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * _PRECISION) / totalDscMinted;
    }

    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_sPriceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return ((uint256(price) * _ADDITIONAL_FEED_PRECISION) * amount) / _PRECISION;
    }
}