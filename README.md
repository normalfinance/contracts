# Normal

[![Build Status](https://travis-ci.org/ensdomains/ens-contracts.svg?branch=master)](https://travis-ci.org/ensdomains/ens-contracts)

For documentation of the Normal Index system, see [docs.normalfinance.io](https://docs.normalfinance.io/).

## npm package

This repo doubles as an npm package with the compiled JSON contracts

```js
import { IndexToken, Vault } from "@normalfinance/contracts";
```

## Importing from solidity

```
import '@normalfinance/contracts/contracts/IndexToken.sol';
import '@normalfinance/contracts/contracts/Vault.sol';

```

## Contracts

### IndexToken

Interface of the ENS Registry.

### Vault

Implementation of the ENS Registry, the central contract used to look up resolvers and owners for domains.

## Developer guide

### Prettier pre-commit hook

This repo runs a husky precommit to prettify all contract files to keep them consistent. Add new folder/files to `prettier format` script in package.json. If you need to add other tasks to the pre-commit script, add them to `.husky/pre-commit`

### How to setup

```
git clone https://github.com/normalfinance/contracts
cd normalfinance-contracts
yarn
```

### How to run tests

```
yarn test
```

### How to publish

```
yarn pub
```

### Release flow

Smart contract development tends to take a long release cycle. To prevent unnecessary dependency conflicts, please create a feature branch (`features/$BRNACH_NAME`) and raise a PR against the feature branch. The feature branch must be merged into master only after the smart contracts are deployed to the Ethereum mainnet.
