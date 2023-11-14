// SPDX-License-Identifier: MIT

/* What are the invariants?
 *
 * 1. The total supply of DSC should be less than the total value of collateral
 * 2. Getter view functions should never revert <- evergreen invariant
 */

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";


contract Invariants is StdInvariant, Test {
    DeployDSC _deployer;
    HelperConfig _config;
    DSCEngine _engine;
    DecentralizedStableCoin _dsc;
    Handler _handler; 
    address _weth;
    address _wbtc;

    function setUp() external {
        _deployer = new DeployDSC();
        (_dsc, _engine, _config) = _deployer.run();
        (,, _weth, _wbtc,) = _config.activeNetworkConfig();
        //targetContract(address(engine));
        _handler = new Handler(_engine, _dsc);
        targetContract(address (_handler));
    }

    function invariantProtocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = _dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(_weth).balanceOf(address(_engine));
        uint256 totalWbtcDeposited = IERC20(_wbtc).balanceOf(address(_engine));

        uint256 wethValue = _engine.getUsdValue(_weth, totalWethDeposited);
        uint256 wbtcValue = _engine.getUsdValue(_wbtc, totalWbtcDeposited);

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("total value: ", totalSupply);
        //console.log("Times mint is called:", timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariantGetterShouldNotRevert() public view {
        //_engine.getAccountCollateralValueInUsd(address);
        //_engine.getAccountInformation(address);
        _engine.getAdditionalFeedPrecision();
        _engine.getLiquidationBonus();
        //_engine.getCollateralBalanceOfUser(address,address);
        //_engine.getCollateralTokenPriceFeed(address);
        _engine.getCollateralTokens();
        _engine.getDsc();
        //_engine.getHealthFactor(address);
        _engine.getLiquidationBonus();
        _engine.getLiquidationPrecision();
        _engine.getLiquidationThreshold();
        _engine.getMinHealthFactor();
        _engine.getPrecision();
        //_engine.getTokenAmountFromUsd(address,uint256);
        //_engine.getUsdValue(address,uint256)    
    }
}