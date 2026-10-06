// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IdentityUnits} from "../src/IdentityUnits.sol";

/// @dev Local factory stand-in; never deployed as part of the project.
contract TokenFactoryProbe {
    function deploy(bytes32 salt) external returns (IdentityUnits) {
        return new IdentityUnits{salt: salt}();
    }

    function move(IdentityUnits token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

contract IdentityUnitsTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    IdentityUnits private token;

    function setUp() public {
        token = new IdentityUnits();
    }

    function test_metadataAndInitialAllocation() public view {
        assertEq(token.name(), "Identity Units");
        assertEq(token.symbol(), "UI");
        assertEq(token.decimals(), 18);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        IdentityUnits fresh = new IdentityUnits();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function testFuzz_constructorCreditsImmediateDeployer(address deployer) public {
        vm.assume(deployer != address(0));
        vm.prank(deployer);
        IdentityUnits fresh = new IdentityUnits();
        assertEq(fresh.balanceOf(deployer), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_create2FactoryAllocationAndExactDistribution() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        bytes32 salt = bytes32(uint256(42));
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(IdentityUnits).creationCode)
                        )
                    )
                )
            )
        );
        IdentityUnits launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);

        // Model the factory-to-distributor transfer and the distributor's claim.
        uint256 share = SUPPLY / 10;
        assertTrue(factory.move(launched, ALICE, share));
        assertEq(launched.balanceOf(ALICE), share);
        vm.prank(ALICE);
        assertTrue(launched.transfer(BOB, share));
        assertEq(launched.balanceOf(ALICE), 0);
        assertEq(launched.balanceOf(BOB), share);
        assertEq(launched.balanceOf(address(factory)), SUPPLY - share);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_transferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 123 ether);
        assertTrue(token.transfer(ALICE, 123 ether));
        assertEq(token.balanceOf(ALICE), 123 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupplyAndOneSmallestUnitBack() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(address(this)), 1);
        assertEq(token.balanceOf(ALICE), SUPPLY - 1);
    }

    function test_selfTransferPreservesBalanceAndSupply() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferToZeroRevertsWithoutBurning() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferToZeroAlsoReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_transferInsufficientBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferMaxUintReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveEmitsEventAndCanBeReplacedOrRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), SPENDER, 100);
        assertTrue(token.approve(SPENDER, 100));
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertTrue(token.approve(SPENDER, 7));
        assertEq(token.allowance(address(this), SPENDER), 7);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_transferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(SPENDER, 100));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 40);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 40));
        assertEq(token.balanceOf(ALICE), 40);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40);
        assertEq(token.allowance(address(this), SPENDER), 60);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 60));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(BOB), 60);
    }

    function test_infiniteAllowancePersistsAndCanBeRevoked() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 100));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 100);
    }

    function test_transferFromInsufficientAllowanceRollsBack() public {
        assertTrue(token.approve(SPENDER, 9));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 9, 10));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 10);
        assertEq(token.allowance(address(this), SPENDER), 9);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_transferFromInsufficientBalanceRestoresAllowance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 100));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 100);
        assertEq(token.allowance(ALICE, SPENDER), 100);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromToZeroRestoresAllowance() public {
        assertTrue(token.approve(SPENDER, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromZeroSenderReverts() public {
        // OpenZeppelin validates the allowance owner before validating the transfer sender.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_deployerCannotSpendHolderBalanceWithoutApproval() public {
        assertTrue(token.transfer(ALICE, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100);
    }

    function test_allowanceBelongsToSpecificSpender() public {
        assertTrue(token.approve(SPENDER, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromToSelfStillConsumesAllowance() public {
        assertTrue(token.approve(SPENDER, 100));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 100));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_noMintBurnOrAdministrativeEntryPoints() public {
        assertTrue(token.transfer(ALICE, 100));
        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[6] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[7] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[8] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[9] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[10] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[11] = abi.encodeWithSignature("setMinter(address)", BOB);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.balanceOf(BOB), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_runtimeContainsNoDangerousOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
            } else {
                assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
            }
        }
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromAccounting(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approved - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_overspendingBalanceReverts(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        assertTrue(token.transfer(ALICE, balance));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, balance + excess)
        );
        vm.prank(ALICE);
        token.transfer(BOB, balance + excess);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_overspendingAllowanceReverts(uint256 approved, uint256 excess) public {
        approved = bound(approved, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - approved);
        assertTrue(token.approve(SPENDER, approved));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, approved + excess
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, approved + excess);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
