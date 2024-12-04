# v4-template

---

### Check Forge Installation

_Ensure that you have correctly installed Foundry (Forge) and that it's up to date. You can update Foundry by running:_

```
foundryup
```

## Set up

_requires [foundry](https://book.getfoundry.sh)_

```
forge install
forge test
```

### Local Development (Anvil)

```bash
# start anvil, a local EVM chain
anvil

npm run build

npm run deploy:core

npm run deploy:avs

# in a new terminal
forge script script/Anvil.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --via-ir --broadcast

npm run start:operator

npm run start:traffic <hookaddress>
```

npm run start:traffic 0xf04EBDe029c221173755e08B35094660b994C0c0
