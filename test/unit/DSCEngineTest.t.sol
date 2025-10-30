// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployDSC} from "../../script/DeployScript.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Test, console} from "@forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Vm} from "@forge-std/Vm.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

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
    // From now
    uint256 amountToMint = 100 ether;
    address private USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 20 ether;
    uint256 public constant STARTING_AMOUNT_MINTED = 20 ether;

    // LIquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    /////////////////
    //// Events ////
    ////////////////

    event CollateralDeposited(address indexed, address indexed, uint256);

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerkey) = config
            .s_activeNetworkConfig();
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

        vm.expectRevert(
            DSCEngine
                .DSCEngine_TokenAddressAndPriceFeedAddressLengthMustBeSame
                .selector
        );
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
    function testDepositCollateralIfAmountIsZeroShouldRevert() public {
        vm.prank(USER);
        ERC20Mock(weth).approve(address(dsce), 0 ether);
        vm.expectRevert(DSCEngine.DSCEngine_NeedMoreThanZero.selector);
        dsce.depositCollateral(address(weth), 0 ether);
        vm.stopPrank();
        assert(dsce.getUserCollateralBalance(USER, weth) == 0 ether);
    }

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
        dsce.depositCollateral(weth, 0 ether);
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
        dsc.approve(address(dsce), AMOUNT_COLLATERAL);
        vm.recordLogs();
        vm.expectEmit(true, true, true, false, address(dsce));
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        console.log("The length of the entries:", entries.length);
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
        dsce.mintDSC(amountToMint);
        vm.stopPrank();
        assertEq(dsce.getUserDSCTokenMinted(USER), amountToMint);
    }

    function testMintOnMintFailed() public depositedCollateral {
        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(dsc.mint.selector, USER, amountToMint),
            abi.encode(false)
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_MintFailed.selector);
        dsce.mintDSC(amountToMint);
        vm.stopPrank();
    }

    //////////////////////////////
    ///// redeemCollateral Test///
    /////////////////////////////
    modifier depositedAndMintedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
        _;
    }

    function testRedeemCollateral() public depositedAndMintedCollateral {
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL - 10 ether);
        console.log("Balance of User : ");
        console.log(ERC20Mock(weth).balanceOf(USER));
        assert(dsce.getUserCollateralBalance(USER, weth) < AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralWithZeroAmount()
        public
        depositedAndMintedCollateral
    {
        uint256 redeemAmount = 0;
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.redeemCollateral(weth, redeemAmount);
        assert(dsce.getUserCollateralBalance(USER, weth) <= AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralWithOverCollateralize()
        public
        depositedAndMintedCollateral
    {
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL + amountToMint);
        vm.stopPrank();
    }

    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testMustRedeemMoreThanZero() public depositedAndMintedCollateral {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert();
        dsce.redeemCollateralForDsc(weth, 0, amountToMint);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        dsc.approve(address(dsce), amountToMint);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData();
        amountToMint = (AMOUNT_COLLATERAL * (uint256(price) * dsce.getAdditionalFeedPrecision())) / dsce.getPrecision();
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getUsdValue(weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    /////////////////////////////////////
    /////////////// Burn Test ///////////
    /////////////////////////////////////

    function testBurn() public depositedAndMintedCollateral {
        vm.startPrank(USER);
        dsc.approve(address(dsce), amountToMint);
        dsce.burnDsc(amountToMint);
        console.log("Balance of User : ");
        console.log(ERC20Mock(weth).balanceOf(USER));
        vm.stopPrank();
    }

    function testBurnDscWithMockCall() public depositedAndMintedCollateral {
        vm.startPrank(USER);
        dsc.approve(address(dsce), amountToMint);
        vm.stopPrank();

        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(
                dsc.transferFrom.selector,
                USER,
                address(dsce),
                amountToMint
            ),
            abi.encode(false)
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_TransferFailed.selector);
        dsce.burnDsc(amountToMint);
        vm.stopPrank();
    }

    //////////////////////////////////////
    ////// redeemCollateralForDsc test///
    ////////////////////////////////////

    function testRedeemCollateralForDsc() public depositedAndMintedCollateral {
        vm.startPrank(USER);
        dsc.approve(address(dsce), amountToMint);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
        assertEq(ERC20Mock(weth).balanceOf(USER), AMOUNT_COLLATERAL);
    }

    //////////////////////////////////////
    //////////// healthFactor test///////
    ////////////////////////////////////
    function testHealthFactorCheckRevertsWhenHealthy()
        public
        depositedAndMintedCollateral
    {
        vm.startPrank(USER);
        vm.expectRevert(
            DSCEngine.DSCEngine_UserIsHealthyCantBeLiquidated.selector
        );
        dsce.liquidate(weth, USER, 1e18);
        vm.stopPrank();
        assert(dsce.getHealthFactor(USER) > 1);
    }

    function testHealthFactorWhenUnhealthy()
        public
        depositedAndMintedCollateral
    {
        uint256 expectedHealthFactor = 200 ether;
        vm.startPrank(USER);
        uint256 healthFactor = dsce.getHealthFactor(USER);
        assert(healthFactor == expectedHealthFactor);
    }

    function testHealthFactorBelowHealthFactor()
        public
        depositedAndMintedCollateral
    {
        int256 updatedEthUsdPrice = 500e8;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(updatedEthUsdPrice);
        vm.startPrank(USER);
        uint256 healthFactor = dsce.getHealthFactor(USER);
        vm.stopPrank();
        assert(healthFactor >= 10);
    }

    /////////////////////////////////////////
    ////////// liquidation /////////////////
    ///////////////////////////////////////
    function testLiquidateRevertsIfDebtToCoverIsZero() public {
        vm.expectRevert();
        dsce.liquidate(address(weth), USER, 0);
    }
    
    function testLiquidateRevertsIfCollateralNotAllowed() public {
        address randomToken = makeAddr("randomToken");
        vm.expectRevert();
        dsce.liquidate(randomToken, USER, 100 ether);
    }

    function testLiquidationWithMaxHealth() public depositedAndMintedCollateral{
        dsc.approve(address(dsce), amountToMint);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_UserIsHealthyCantBeLiquidated.selector);
        dsce.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    function testliquidationWithTranferFailedError() public depositedAndMintedCollateral{
        // liquidator also started to position in the DAO
        ERC20Mock(weth).mint(liquidator , AMOUNT_COLLATERAL);
        vm.startPrank(liquidator);
        // approved by dsce to use the collateral of liquidator
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        
        dsc.approve(address(dsce), amountToMint);

        int256 updatedPrice =  8e8;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(updatedPrice);
        // collateral money
        
        vm.startPrank(liquidator);
        dsce.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    
    ////////////////////////////////////////
    ////// Public function test ////////////
    ///////////////////////////////////////

    function testAccountCollateralValue() public depositedAndMintedCollateral {
        assert(dsce.getAccountCollateralValue(USER) > 0);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 ethAmount = dsce.getTokenAmountFromUsd(weth, 2000e8);
        assertGt(ethAmount, 0);
    }
}
