# Identity Units (UI)

Identity Units is a fixed-supply ERC-20. Deployment creates exactly **1,000,000,000 UI** with **18 decimals**, all credited to the immediate constructor caller.

| Deployment parameter | Value |
| --- | --- |
| Contract | `src/IdentityUnits.sol:IdentityUnits` |
| Name | `Identity Units` |
| Symbol | `UI` |
| Decimals | `18` |
| Total supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`; encoded arguments `0x`) |
| Native currency sent at deployment | `0` |
| Initial recipient | Constructor `msg.sender` |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimization | Enabled, 200 runs |
| Metadata bytecode hash | None |

## Behavior and assumptions

The request is interpreted as a standard, freely transferable ERC-20. The name does not impose identity verification or transfer eligibility. The token uses the vendored OpenZeppelin Contracts v5.2.0 ERC-20 implementation.

- Minting occurs only in the constructor. There is no external mint or burn function, owner, pause, blacklist, seizure, upgrade, tax, rebase, or transaction limit.
- Successful transfers deliver the exact requested amount and return `true`. Invalid transfers revert with OpenZeppelin ERC-20 custom errors. Transfers and approvals to the zero address revert. Zero-value transfers between valid addresses are allowed and emit `Transfer`.
- `approve` replaces the allowance and emits `Approval`. `transferFrom` requires the caller's allowance and consumes it, except that `type(uint256).max` represents an unlimited allowance and remains unchanged. Spending an allowance does not emit `Approval` in this OpenZeppelin version; query `allowance` for its current value.
- The constructor emits one `Transfer` from the zero address for the entire supply. All subsequent transfers conserve supply. Token operations make no external calls or recipient callbacks.
- An EOA deploying directly receives the supply. When a factory deploys via CREATE or CREATE2, the factory receives it; neither the factory's caller nor `tx.origin` receives tokens automatically. The factory must support forwarding its tokens. A contract that cannot forward them can lock the full supply permanently.

## Build and check

With Foundry and Solidity 0.8.26 available:

```sh
forge build
forge test
forge fmt --check
```

The compiler is pinned by version in `foundry.toml`. All Solidity dependencies and their licenses are ordinary files under `lib/`; builds require no package installation, Git submodules, or dependency downloads. An offline verifier needs the pinned compiler installed. FFI and filesystem cheatcode access are disabled. Tests use no environment variables, RPC endpoint, fork, wallet, or shared external state.

The suite includes metadata and constructor-event checks, EOA and CREATE2 factory allocation, exact distributor/claim transfers, finite and unlimited approvals, revocation, zero and self-transfers, smallest-unit and full-supply transfers, insufficient balances/allowances, invalid addresses, revert atomicity, and unauthorized administrative calls. Five fuzz tests run 512 cases each. Two stateful invariants run 128 sequences of 64 calls each, checking constant supply and conservation across a closed set of holders. The handler also checks exact balances and allowance changes after every successful operation.

The supplied protected launch harness is an external integration check that requires the network's factory, Uniswap v4 contracts, and launch parameters. The local distribution test covers token transfer behavior; it does not simulate a real pool or establish that the external launch harness passed.

## Deployment and operation

Obtain the creation bytecode and ABI locally, without broadcasting:

```sh
forge inspect src/IdentityUnits.sol:IdentityUnits bytecode
forge inspect src/IdentityUnits.sol:IdentityUnits abi
```

Deploy that creation bytecode with no appended constructor arguments and no native value. No initialization transaction or library linking is required. In a launch manifest, use the exact contract identifier, metadata, empty constructor argument list, and smallest-unit supply from the table. There are no application contracts in this project.

The network deployer is responsible for choosing a Cancun-compatible target chain, verifying the factory and deployment configuration, arranging secure custody and onward distribution, and checking the deployed source/bytecode and initial allocation. A factory launch's distributor, pool, and subsequent allocations are responsibilities of the launch infrastructure. The token applies no fee or exemption to those addresses. Pair currency, pool share, opening valuation, and remainder recipient were not supplied here and must come from the authorized launch configuration; this project does not invent those parameters.

After deployment, verify `name`, `symbol`, `decimals`, `totalSupply`, the mint event, and the constructor recipient's balance before further distribution. For CREATE2, the operator must use the intended factory, salt, and exact creation bytecode to predict the address. Source verification should use the settings above.

Holders control transfers and approvals. There is no administrator who can recover mistaken transfers, rescue assets sent to the token contract, freeze compromised accounts, or upgrade this deployment. Prefer allowances limited to the intended spend. To replace a nonzero allowance, revoke it to zero and wait for confirmation before approving the new amount, accounting for any spending that occurs before revocation. An unlimited approval allows the spender to spend both present and future balances until revoked.

This assignment performs local compilation and tests only; it does not deploy or broadcast transactions. The tests are not an independent security audit. The launch operator should arrange the independent adversarial review required by the contributor network before release. Slither, Mythril, and a live pool integration were not run.
