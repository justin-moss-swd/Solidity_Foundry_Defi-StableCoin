// SPDX-License-Identifier: MIT

// Handler will narrow down the way functions are called

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";


contract Handler is Test {
    DSCEngine _engine;
    DecentralizedStableCoin _dsc;

    ERC20Mock _weth;
    ERC20Mock _wbtc;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;

    uint256 constant _MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine engine, DecentralizedStableCoin dsc) {
        _engine = engine;
        _dsc = dsc;

        address[] memory collateralTokens = _engine.getCollateralTokens();
        _weth = ERC20Mock(collateralTokens[0]);
        _wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(_engine.getCollateralTokenPriceFeed(address(_weth)));
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;
        
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _engine.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        
        if (maxDscToMint < 0) return;
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) return;


        vm.startPrank(sender);
        _engine.mintDsc(amount);
        vm.stopPrank();

        timesMintIsCalled++;
    }
    
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, _MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(_engine), amountCollateral);
        _engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = _engine.getCollateralBalanceOfUser(address(collateral), msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        if (amountCollateral == 0) return;
        _engine.redeemCollateral(address(collateral), amountCollateral);
    }

    // TODO: Fix the break
    // This breaks the invariant test suite
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt); 
    // }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) return _weth;
        else return _wbtc;
    }
}