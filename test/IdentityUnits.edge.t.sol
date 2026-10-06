// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IdentityUnits} from "src/IdentityUnits.sol";

/// @dev Complements the deployment and basic ERC-20 tests with authorization and arithmetic edges.
/// forge-config: default.fuzz.runs = 1000
contract IdentityUnitsEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    IdentityUnits private token;

    function setUp() public {
        token = new IdentityUnits();
    }

    function test_maximumMinusOneIsFiniteAndFullSupplyCanBeSpent() public {
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        uint256 remaining = type(uint256).max - 1 - SUPPLY;
        assertEq(token.allowance(address(this), SPENDER), remaining);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), remaining);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_exhaustedAllowanceCannotBeUsedTwice() public {
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_transferFromByOwnerRequiresItsOwnAllowance() public {
        // Owning the tokens does not implicitly approve the transferFrom entry point.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_allowanceCannotBeBorrowedFromAnotherOwner() public {
        assertTrue(token.transfer(ALICE, 2));
        assertTrue(token.transfer(BOB, 2));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(BOB, SPENDER, 1);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(BOB), 2);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.allowance(BOB, SPENDER), 0);
    }

    function test_zeroDelegatedTransferToZeroStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, address(0), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacingAllowanceLimitsTheNextSpend(uint256 initialApproval, uint256 replacement) public {
        replacement = bound(replacement, 0, SUPPLY - 1);
        assertTrue(token.approve(SPENDER, initialApproval));
        assertTrue(token.approve(SPENDER, replacement));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, replacement, replacement + 1
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, replacement + 1);
        assertEq(token.allowance(address(this), SPENDER), replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);

        // Rejection must not poison the still-authorized transfer.
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, replacement));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY - replacement);
    }

    function testFuzz_insufficientBalancePreservesArbitraryAllowance(uint256 balance, uint256 amount, uint256 approval)
        public
    {
        balance = bound(balance, 0, SUPPLY - 1);
        amount = bound(amount, balance + 1, type(uint256).max);
        approval = bound(approval, amount, type(uint256).max);
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approval));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approval);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_roundTripPreservesBalancesAndApprovals(uint256 amount, uint256 approval) public {
        amount = bound(amount, 1, SUPPLY);
        assertTrue(token.transfer(ALICE, amount));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approval));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(ALICE, SPENDER), approval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splittingDelegatedTransferMatchesSingleTransfer(uint256 approval, uint256 amount, uint256 first)
        public
    {
        amount = bound(amount, 0, approval < SUPPLY ? approval : SUPPLY);
        first = bound(first, 0, amount);
        IdentityUnits single = new IdentityUnits();
        assertTrue(single.approve(SPENDER, approval));
        assertTrue(token.approve(SPENDER, approval));
        vm.prank(SPENDER);
        assertTrue(single.transferFrom(address(this), ALICE, amount));
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        assertTrue(token.transferFrom(address(this), ALICE, amount - first));
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), single.balanceOf(ALICE));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.allowance(address(this), SPENDER), single.allowance(address(this), SPENDER));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), SPENDER), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
