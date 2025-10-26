// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;
import {Script} from "@forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src//DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns(DecentralizedStableCoin ,DSCEngine) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) = config.s_activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        (DecentralizedStableCoin dsc , DSCEngine engine) = deployer(msg.sender,tokenAddresses, priceFeedAddresses, deployerKey);
        return (dsc, engine);
    }   

    /**
     * @notice Deploy a Decentralized Stable Coin and DSCEngine
     * @return return the DecentralizedStableCoin and DSCEngine
     */
    function deployer(address deploy , address[] memory tokenAddress ,address[] memory priceFeedAddress, uint256 deployerKey) public  returns (DecentralizedStableCoin, DSCEngine) {
        vm.startBroadcast();
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(deploy);
        DSCEngine dscEngine = new DSCEngine(tokenAddress, priceFeedAddress, address(dsc));
        return (dsc, dscEngine);
        vm.stopBroadcast();
    }
}