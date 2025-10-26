// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployDSC} from "../../script/DeployScript.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Test, console} from "@forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerkey;

    address private USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_AMOUNT_MINTED = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerkey) = config.s_activeNetworkConfig();
        dsc.transferOwnership(address(dsce));
        ERC20Mock(weth).mint(USER,STARTING_AMOUNT_MINTED);
    }  

    ///////////////////////////////
    //// getUsdValue Test ////////
    /////////////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18; // 15,000,000,000 wei
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth , ethAmount);
        console.log("Expected USD: ", expectedUsd);
        assertEq(actualUsd, expectedUsd );
    }
    /**
     * @notice Test case for getUsdValue with zero amount.
     */
    function testGetUsdValueWithZeroAmount() public  {
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth , 0);
        console.log("Expected USD: ", expectedUsd);
        assertEq(actualUsd, 0);
    }

    ////////////////////////////////
    ///// depositCollateral Test///
    ///////////////////////////////

    function testDepositCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth,AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
    function testDepositCollateralIfAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine_NeedMoreThanZero.selector);
        dsce.depositCollateral(weth,0);
        vm.stopPrank();
    }

    //////////////////////////////
    ///// redeemCollateral Test///
    /////////////////////////////

    function testRedeemCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 100000);
        vm.stopPrank();

        vm.startBroadcast(USER);
        dsce.redeemCollateral(weth,AMOUNT_COLLATERAL - 1000000);
        console.log("Balance of User : ");
        console.log(ERC20Mock(weth).balanceOf(USER));
        assert(dsce.getUserCollateralBalance(USER, weth) < AMOUNT_COLLATERAL);
        vm.stopPrank();
    }


}
