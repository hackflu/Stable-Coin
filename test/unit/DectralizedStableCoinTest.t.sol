// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "@forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    // error DecentralizedStableCoin_BurnAmountExceedsBalance();

    DecentralizedStableCoin s_stableCoin;
    address public USER = makeAddr("user");
    address public to = makeAddr("to");

    function setUp() external {
        s_stableCoin = new DecentralizedStableCoin(USER);
    }

    function testMint() public {
        uint256 amount = 2;
        vm.startPrank(USER);
        bool sucess = s_stableCoin.mint(to, amount);
        vm.stopPrank();
        assert(sucess == true);
        assert(keccak256(bytes(s_stableCoin.name())) == keccak256(bytes("DecentralizedCoin")));
        assert(keccak256(bytes(s_stableCoin.symbol())) == keccak256(bytes("DSC")));
        assert(s_stableCoin.balanceOf(to) > 0);
    }

    function test_RevertIf_MintAmountIsZero() public {
        uint256 amount = 0;
        vm.startPrank(USER);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin_BurnAmountExceedsBalance.selector);
        s_stableCoin.mint(to, amount);
        vm.stopPrank();
    }

    function testToAddress() public {
        uint256 amount = 0;
        vm.startPrank(USER);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin_NotZeroAddress.selector);
        s_stableCoin.mint(address(0), amount);
        vm.stopPrank();
    }

    function testBurn() public {
        uint256 amount = 2;
        vm.startPrank(USER);
        bool sucess = s_stableCoin.mint(USER, amount);
        vm.stopPrank();

        vm.startPrank(USER);
        s_stableCoin.burn(amount);
        vm.stopPrank();
        assert(s_stableCoin.balanceOf(to) == 0);
    }
}
