# Vendored dependencies

Dependencies are copied as ordinary source files, with upstream license files retained. No dependency installer runs during build or test.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.2.0) | `v5.2.0` | ERC20 and its four transitive Solidity imports | `lib/openzeppelin-contracts/LICENSE` (MIT) |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | `src/` | `lib/forge-std/LICENSE-MIT`, `lib/forge-std/LICENSE-APACHE` |

The source files are unmodified upstream copies. These SHA-256 digests identify the downloaded release archives:

```text
80f86d2dba4e1c0d66a216d2ddf0ac5d731edf9338ea12a985edca8774802814  https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.2.0
45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94  https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
```

`remappings.txt` resolves both dependencies locally. OpenZeppelin is the only production dependency; forge-std is used by tests. `DEPENDENCIES.sha256` records individual file hashes and can be checked with `sha256sum -c DEPENDENCIES.sha256`.
