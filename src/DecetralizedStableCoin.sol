// SPDX-License-Identifier: MIT

// Layout of the contract file:
// version
// imports
// errors
// interfaces, libraries, contract

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

pragma solidity ^0.8.18;
import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedCoin
 * @author devilknowyou
 * collateral: Exogenous (ETH & BTC)
 * Minitng : Algorithmic
 * Realtive Stability : Pegged to USD
 *
 * @dev This is the contract to be goverened by DSCEngine
 */

contract DectralizedStableCoin is ERC20Burnable, Ownable {
    error DectralizedStableCoin_MustBeMoreThanZero();
    error DectralizedStableCoin_BurnAmountExceedsBalance();
    error DectralizedStableCoin_NotZeroAddress();
    error DectralizedStableCoin_BurnAmountExceedsBalance();

    constructor() ERC20("DecentralizedCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if(_amount <= 0){
            revert DectralizedStableCoin_MustBeMoreThanZero();
        }
        if(_amount > balance) {
            revert DectralizedStableCoin_BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to , uint256 _amount) external onlyOwner returns(bool){
        if( to == address(0)){
            revert DectralizedStableCoin_NotZeroAddress();
        }
        if(_amount <= 0){
            revert DectralizedStableCoin_BurnAmountExceedsBalance();
        }
        _mint(to , _amount);
        return true;

    } 
}
