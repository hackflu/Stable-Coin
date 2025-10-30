// SPDX-License-Identifier: MIT

// Layout of the contract file:
// version
// imports
// interfaces, libraries, contract
// errors

// Inside Contract:
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.21;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Devilknowyou
 * @notice The system is desgined to be as minimal as possible , and have the
 * token maintain as 1 token = $1 peg
 * The stableCoin has a property:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmic Minting
 *
 * Similar to DAI had no governace , no fees and was only backed by WETH and WBTC
 * @notice This contract is the core od the DSC System.It handles all the logic for mining and
 * redmeeing DSC , as well as depositing $ withdrawing collateral
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////
    //// Errors //////
    //////////////////
    error DSCEngine_NeedMoreThanZero();
    error DSCEngine_TokenAddressAndPriceFeedAddressLengthMustBeSame();
    error DSCEngine_NotAllowedToken();
    error DSCEngine_TransferFailed();
    error DSCEngine_BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine_MintFailed();
    error DSCEngine_UserIsHealthyCantBeLiquidated();
    error DSCEngine_HealthfactorNotImproved();
    /////////////////////
    // State variables //
    ////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateralToken;
    DecentralizedStableCoin private i_dsc;

    /////////////////////
    ///// Events ///////
    ////////////////////
    event CollateralDeposited(address indexed, address indexed, uint256);
    event CollateralWithdrawn(address indexed, address indexed, uint256);
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );
    ///////////////////
    //// Modifiers ////
    //////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine_NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowed(address token) {
        if (s_priceFeed[token] == address(0)) {
            revert DSCEngine_NotAllowedToken();
        }
        _;
    }

    ///////////////////
    // constructor ///
    //////////////////

    constructor(
        address[] memory tokenAddress,
        address[] memory priceFeedAddress,
        address dscAddress
    ) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine_TokenAddressAndPriceFeedAddressLengthMustBeSame();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeed[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralToken.push(tokenAddress[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////
    //External function//
    ////////////////////
    /**
     * @notice This function will deposit the collateral and mint DSC
     * @param tokenCollateralAddress to get token collateral address
     * @param amountCollateral the amount to put as collateral
     * @param amountDscToMint amoount of DSC token to min
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /**
     * @notice Use CEI (checks ,effects ,interaction)
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowed(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool sucess = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!sucess) {
            revert DSCEngine_TransferFailed();
        }
    }

    /*
     * @notice already used the healthFactor in the redeemCollateralForDsc function
     * @param tokenCollateralAddress token of the collateral address
     * @param amountCollateral amount as collateral deposited
     * @param amountDscToBurn amount to Dsc token to burn
     */
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountOfCollateral,
        uint256 amountDscToBurn
    )
        external
        moreThanZero(amountOfCollateral)
        isAllowed(tokenCollateralAddress)
    {
        _burnDsc(msg.sender, msg.sender, amountDscToBurn);
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountOfCollateral
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice follow CIE.
     * @notice They must have collateral value greater than the minimum threshold
     * @param address tokenCollateralAddress The address of the token to redeem as collateral
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountOfCollateral
    )
        public
        moreThanZero(amountOfCollateral)
        nonReentrant
        isAllowed(tokenCollateralAddress)
    {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountOfCollateral
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice follow CIE
     * @param anountDscToMint The amount of centralized stablecoin to mint
     * @notice They must have collateral value greater than the minimum threshold
     */
    function mintDSC(uint256 amountDscToMint) public nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine_MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(msg.sender, msg.sender, amount);
        _revertIfHealthFactorIsBroken(msg.sender); // I dont think this is necessary
    }

    /*
     * @param collateral Liquidater choose which collateral address to target
     * @param user which user want to liquidate
     * @param debtToCover amount of debt to cover
     * @notice This function will return the collateral value of the user in return of the given user
     * @notice The liquidator will get the bonus with the debt amount
     * @notice This function will work assuming the protocol is roughtly 200%
     * @notice A known bug would be if the protocol is 100% or less collaterllized, then we
     * would't be able to inciate the liquidators.
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) isAllowed(collateral) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor > MIN_HEALTH_FACTOR) {
            revert DSCEngine_UserIsHealthyCantBeLiquidated();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralRedeemed = tokenAmountFromDebtCovered +
            bonusCollateral;

        _redeemCollateral(
            user,
            msg.sender,
            collateral,
            totalCollateralRedeemed
        );
        _burnDsc(user, msg.sender, debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine_HealthfactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    //////////////////////////////////
    //private internal view function//
    /////////////////////////////////
    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValue)
    {
        totalDscMinted = s_DscMinted[user];
        totalCollateralValue = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral value
        (
            uint256 totalDscMinted,
            uint256 totalCollateralValueInUse
        ) = _getAccountInformation(user);
        return  _calculateHealthFactor(totalDscMinted, totalCollateralValueInUse);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. check health
        //2. revert
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine_BreaksHealthFactor(healthFactor);
        }
    }

    function _burnDsc(
        address onBehalfOf,
        address dscFrom,
        uint256 amountDscToBurn
    ) private {
        s_DscMinted[onBehalfOf] -= amountDscToBurn;

        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );
        // This conditional is hypothetically unreachable
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    //////////////////////////////////
    //public external view function//
    /////////////////////////////////
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralToken.length; i++) {
            address token = s_collateralToken[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeed[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getUserCollateralBalance(
        address user,
        address token
    ) public view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getUserDSCTokenMinted(address user) public view returns (uint256) {
        return s_DscMinted[user];
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeed[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

}
