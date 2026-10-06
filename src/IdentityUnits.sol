// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Identity Units (UI)
/// @notice Fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract IdentityUnits is ERC20 {
    /// @notice One billion UI, expressed in the token's smallest units.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deployer.
    /// @dev A factory deployment credits the factory, not tx.origin.
    constructor() ERC20("Identity Units", "UI") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
