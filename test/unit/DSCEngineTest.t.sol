// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployDSC} from "../../script/DeployScript.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Test, console} from "@forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Vm} from "@forge-std/Vm.sol";

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
    /////////////////
    //// Events ////
    ////////////////

    event CollateralDeposited(address indexed, address indexed, uint256);

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerkey) = config.s_activeNetworkConfig();
        dsc.transferOwnership(address(dsce));
        ERC20Mock(weth).mint(USER, STARTING_AMOUNT_MINTED);
    }

    ////////////////////////////////
    ////// constructor test ///////
    //////////////////////////////
    address[] public tokenAddress;
    address[] public priceFeeds;

    function testRevertIfTokenLengthDosentMatchPriceFeeds() public {
        tokenAddress.push(weth);
        priceFeeds.push(wethUsdPriceFeed);
        priceFeeds.push(wbtcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine_TokenAddressAndPriceFeedAddressLengthMustBeSame.selector);
        new DSCEngine(tokenAddress, priceFeeds, address(dsc));
    }

    ///////////////////////////////
    //// getUsdValue Test ////////
    /////////////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18; // 15,000,000,000 wei
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        console.log("Expected USD: ", expectedUsd);
        assertEq(actualUsd, expectedUsd);
    }

    /**
     * @notice Test case for getUsdValue with zero amount.
     */
    function testGetUsdValueWithZeroAmount() public view {
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, 0);
        console.log("Expected USD: ", expectedUsd);
        assertEq(actualUsd, 0);
    }

    ////////////////////////////////
    ///// depositCollateral Test///
    ///////////////////////////////

    function testDepositCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositCollateralIfAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine_NeedMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock rankToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_NotAllowedToken.selector);
        dsce.depositCollateral(address(rankToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testEventDepositCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.recordLogs();
        vm.expectEmit(true, true, false, false);
        emit CollateralDeposited(USER, weth, 100000);
        dsce.depositCollateral(weth, 100000);
        vm.stopPrank();
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 3);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    ////////////////////////////////
    ///// Mint Test/////////////////
    ///////////////////////////////
    function testMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        dsce.mintDSC(100000);
        vm.stopPrank();
        assertEq(dsce.getUserDSCTokenMinted(USER), 100000);
    }

    function testMintOnMintFailed() public depositedCollateral {
        vm.mockCall(address(dsc), abi.encodeWithSelector(dsc.mint.selector, USER, 100000), abi.encode(false));
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_MintFailed.selector);
        dsce.mintDSC(100000);
        vm.stopPrank();
    }

    //////////////////////////////
    ///// redeemCollateral Test///
    /////////////////////////////
    modifier depositedAndMintedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 100000);
        vm.stopPrank();
        _;
    }

    function testRedeemCollateral() public depositedAndMintedCollateral {
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL - 1000000);
        console.log("Balance of User : ");
        console.log(ERC20Mock(weth).balanceOf(USER));
        assert(dsce.getUserCollateralBalance(USER, weth) < AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralWithZeroAmount() public depositedAndMintedCollateral {
        uint256 redeemAmount = 0;
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.redeemCollateral(weth, redeemAmount);
        assert(dsce.getUserCollateralBalance(USER, weth) <= AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralWithOverCollateralize() public depositedAndMintedCollateral {
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL + 1000000);
        vm.stopPrank();
    }

    /////////////////////////////////////
    /////////////// Burn Test ///////////
    /////////////////////////////////////

    function testBurn() public depositedAndMintedCollateral {
        vm.startPrank(USER);
        dsc.approve(address(dsce), 100000);
        dsce.burnDsc(100000);
        console.log("Balance of User : ");
        console.log(ERC20Mock(weth).balanceOf(USER));
        vm.stopPrank();
    }

    function testBurnDscWithMockCall() public depositedAndMintedCollateral {
        vm.startPrank(USER);
        dsc.approve(address(dsce), 100000);
        vm.stopPrank();

        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(dsc.transferFrom.selector, USER, address(dsce), 100000),
            abi.encode(false)
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_TransferFailed.selector);
        dsce.burnDsc(100000);
        vm.stopPrank();
    }

    //////////////////////////////////////
    ////// redeemCollateralForDsc test///
    ////////////////////////////////////

    function testRedeemCollateralForDsc() public depositedAndMintedCollateral {
        vm.startPrank(USER);
        dsc.approve(address(dsce), 100000);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, 100000);
        vm.stopPrank();
        assertEq(ERC20Mock(weth).balanceOf(USER), AMOUNT_COLLATERAL);
    }

    ////////////////////////////////////////
    //////AccountCollateralValue test ///
    ///////////////////////////////////////

    function testAccountCollateralValue() public depositedAndMintedCollateral {
        assert(dsce.getAccountCollateralValue(USER) > 0);
    }

    ////////////////////////////////////////
    /////// getTokenAmountFromUsd //////////
    ///////////////////////////////////////

    function testGetTokenAmountFromUsd() public view{
        uint256 ethAmount = dsce.getTokenAmountFromUsd(weth, 2000e8);
        assertGt(ethAmount, 0);
    }

    //////////////////////////////////////
    //////////// healthFactor test///////
    ////////////////////////////////////
    function testHealthFactorCheckRevertsWhenLow() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 15e18);
        vm.expectRevert(DSCEngine.DSCEngine_UserIsHealthyCantBeLiquidated.selector);
        dsce.liquidate(weth, USER, 1e18);
        vm.stopPrank();
    }


}
