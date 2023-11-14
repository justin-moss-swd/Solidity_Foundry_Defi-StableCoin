// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";


contract DSCEngineTest is Test{
    DeployDSC _deployer;
    DecentralizedStableCoin _dsc;
    DSCEngine _engine;
    HelperConfig _config;
    address _ethUsdPriceFeed;
    address _weth;
    address _btcUsdPriceFeed;
    address _wbtc;
    uint256 _deployerKey;

    uint256 _amountCollateral = 10 ether;
    uint256 _amountToMint = 100 ether;
    address public user = address(1);
    
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether; 
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    function setUp() public {
        _deployer = new DeployDSC();
        (_dsc, _engine, _config) = _deployer.run();
        (_ethUsdPriceFeed, _btcUsdPriceFeed, _weth, , ) = _config.activeNetworkConfig();
        ERC20Mock(_weth).mint(user, STARTING_ERC20_BALANCE);
    }

    // ==========================================
    // Modifiers
    // ==========================================

    modifier _depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(_weth).approve(address(_engine), AMOUNT_COLLATERAL);
        _;
    }


    // ==========================================
    // Constructor Tests
    // ==========================================
    
    address[] public tokenAddress;
    address[] public priceFeedAddresses;
    
    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddress.push(_weth);
        priceFeedAddresses.push(_ethUsdPriceFeed);
        priceFeedAddresses.push(_btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddress, priceFeedAddresses, address(_dsc));
    }

    
    // ==========================================
    // Price Tests
    // ==========================================
    
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
          // 15e18 ETH * $2000/ETH = 30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = _engine.getUsdValue(_weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUSD() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = _engine.getTokenAmountFromUsd(_weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }


    // ==========================================
    // Deposit Collateral Tests
    // ==========================================

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        
        ERC20Mock(_weth).approve(address(_engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        _engine.depositCollateral(_weth, 0);

        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", user, AMOUNT_COLLATERAL);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        _engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositedCollateralAndGetAccountInfo() public _depositedCollateral{
        // (uint256 totalDscMinted, uint256 collateralValueInUsd) = _engine.getAccountInformation(user);
 
        // uint256 expectedTotalDscMinted = 0;
        // uint256 expectedDepositAmount = _engine.getTokenAmountFromUsd(_weth, collateralValueInUsd);
               
        // assertEq(totalDscMinted, expectedTotalDscMinted);
        // assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _engine.getAccountInformation(user);
        uint256 expectedDepositedAmount = _engine.getTokenAmountFromUsd(_weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedAmount, _amountCollateral);
    }

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(_ethUsdPriceFeed).latestRoundData();
        _amountToMint = (_amountCollateral * (uint256(price) * _engine.getAdditionalFeedPrecision())) / _engine.getPrecision();
        
        vm.startPrank(user);
        ERC20Mock(_weth).approve(address(_engine), _amountCollateral);
        uint256 expectedHealthFactor = _engine.calculateHealthFactor(_amountToMint, _engine.getUsdValue(_weth, _amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        
        _engine.depositCollateralAndMintDsc(_weth, _amountCollateral, _amountToMint);
        vm.stopPrank();
    }

}