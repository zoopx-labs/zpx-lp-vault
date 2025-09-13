## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy Phase‑1

The `script/Deploy_Phase1.s.sol` script requires the following environment variables to be set when running via `forge script`:

- USDC_TOKEN
- USDT_TOKEN
- DAI_TOKEN
- DIA_USDC_FEED
- DIA_USDT_FEED
- DIA_DAI_FEED
- TIMELOCK_ADMIN (optional; if unset the script will use the caller address)

Phase-1 deploy notes:
- All stablecoin token decimals are assumed to be 6 (USDC/USDT).
- DIA feed price decimals must be provided via env vars and must be either 8 or 18.

Dry-run (Arbitrum Sepolia)

Required envs for dry-run: RPC_URL, PRIVATE_KEY, TIMELOCK_ADMIN, USDC_TOKEN, USDT_TOKEN, DAI_TOKEN, DIA_USDC_FEED, DIA_USDT_FEED, DIA_DAI_FEED, DIA_USDC_FEED_DECIMALS, DIA_USDT_FEED_DECIMALS, DIA_DAI_FEED_DECIMALS

Run the dry-run script with forge (no addresses are included here):

```shell
forge script script/DryRun_Sepolia.s.sol \
	--rpc-url $RPC_URL --broadcast --verify --slow --legacy -vvvv
```

Example (local):

Run the script via `forge script` and set the env vars as normal in your shell or a .env file.

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
