// SPDX-License-Identifier: MIT

// /* What are the invariants?
//  *
//  * 1. The total supply of DSC should be less than the total value of collateral
//  * 2. Getter view functions should never revert <- evergreen invariant
//  */

pragma solidity ^0.8.19;

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/Test.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";


// contract OpenInvariantsTest is StdInvariant, Test {
//     DeployDSC public deployer;
//     HelperConfig public config;
//     DSCEngine public engine;
//     DecentralizedStableCoin public dsc;
    
//     address public ethUsdPriceFeed;
//     address public btcUsdPriceFeed;
//     address public weth;
//     address public wbtc;

//     function setUp() external {
//         deployer = new DeployDSC();
//         (dsc, engine, config) = deployer.run();
//         (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
//         targetContract(address(engine));
//     }

//     function invariantProtocolMustHaveMoreValueThanTotalSupply() public view {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = ERC20Mock(weth).balanceOf(address(engine));
//         uint256 totalWbtcDeposited = ERC20Mock(wbtc).balanceOf(address(engine));

//         uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

//         console.log("weth value: %s", wethValue);
//         console.log("wbtc value: %s", wbtcValue);
//         console.log("total value: %s", totalSupply);

//         assert(wethValue + wbtcValue >= totalSupply);
//     }
// }