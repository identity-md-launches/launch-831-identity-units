// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IdentityUnits} from "../src/IdentityUnits.sol";

/// @dev Closed set of holders lets the invariant sum every reachable balance.
contract IdentityUnitsHandler is Test {
    IdentityUnits public immutable token;
    address[4] public actors;

    constructor() {
        token = new IdentityUnits();
        actors = [address(this), address(0xA11CE), address(0xB0B), address(0xCAFE)];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 beforeFrom = token.balanceOf(from);
        uint256 beforeTo = token.balanceOf(to);
        amount = bound(amount, 0, beforeFrom);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? beforeFrom : beforeFrom - amount);
        assertEq(token.balanceOf(to), from == to ? beforeTo : beforeTo + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Include revocation, finite approval and maximum allowance in sequences.
        if (amount != type(uint256).max) amount = bound(amount, 0, token.totalSupply());
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = token.allowance(from, spender);
        uint256 beforeFrom = token.balanceOf(from);
        uint256 beforeTo = token.balanceOf(to);
        amount = bound(amount, 0, approved < beforeFrom ? approved : beforeFrom);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        assertEq(token.balanceOf(from), from == to ? beforeFrom : beforeFrom - amount);
        assertEq(token.balanceOf(to), from == to ? beforeTo : beforeTo + amount);
        assertEq(token.allowance(from, spender), approved == type(uint256).max ? approved : approved - amount);
    }
}

contract IdentityUnitsInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IdentityUnitsHandler private handler;
    IdentityUnits private token;

    function setUp() public {
        handler = new IdentityUnitsHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAlwaysEqualsOneBillionUI() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_allBalancesConserveSupply() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
    }
}
