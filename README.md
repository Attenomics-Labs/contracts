## Learn About Protocol Architecture

For detailed information on the protocol architecture, please see our [Architecture Documentation](./Architecture.md).


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

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

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
# contracts

# Attenomics Contracts

## TokenSwapRouter

The TokenSwapRouter enables seamless swaps between any two creator tokens using their respective bonding curves. It implements a two-step swap process: Token A → ETH → Token B.

### How it Works

1. **Swap Process**:
   ```
   User's Token A → Bonding Curve A (sell) → ETH → Bonding Curve B (buy) → User receives Token B
   ```

2. **Key Features**:
   - Slippage Protection (max 10%)
   - Deadline Checks
   - Router Fee (0.1%)
   - Reentrancy Protection
   - Emergency Withdrawal

3. **Usage Example**:
   ```solidity
   // 1. Get expected output first
   (uint256 expectedOutput, , uint256 minOutput) = router.getExpectedOutput(
       tokenA,
       tokenB,
       amountToSwap
   );

   // 2. Approve router to spend your tokens
   tokenA.approve(address(router), amountToSwap);

   // 3. Execute the swap
   router.swapExactTokensForTokens(
       tokenA,          // Token to sell
       tokenB,          // Token to buy
       amountToSwap,    // Amount of tokenA to swap
       minOutput,       // Minimum amount of tokenB to receive
       deadline         // Transaction deadline
   );
   ```

4. **Safety Features**:
   - Automatic refund of tokens on failed swaps
   - ETH refund on failed buys
   - Bonding curve validation
   - Slippage protection

5. **Events**:
   ```solidity
   event TokenSwap(
       address indexed user,
       address indexed tokenA,
       address indexed tokenB,
       uint256 amountIn,
       uint256 amountOut,
       uint256 ethValue
   );

   event SwapFailed(
       address indexed user,
       address indexed tokenA,
       address indexed tokenB,
       uint256 amountIn,
       string reason
   );
   ```

6. **Error Handling**:
   - `DeadlineExpired()`: Swap attempted after deadline
   - `ExcessiveSlippage()`: Output amount below minimum
   - `InvalidToken()`: Invalid token address or same tokens
   - `SwapFailed()`: General swap failure
   - `TokenTransferFailed()`: Token transfer failed

7. **Protocol Fees**:
   - Router Fee: 0.1% (ROUTER_FEE = 10, FEE_PRECISION = 10000)
   - Fees are collected in ETH during the swap process
   - Fees are sent to the feeCollector address

### Integration Notes

1. **Prerequisites**:
   - Tokens must be registered in the EntryPoint
   - Tokens must have associated bonding curves
   - Users must approve the router to spend their tokens

2. **Best Practices**:
   - Always check getExpectedOutput() before swapping
   - Use reasonable deadlines (e.g., block.timestamp + 20 minutes)
   - Consider gas costs when setting minimum output

3. **Security Considerations**:
   - Contract is nonReentrant
   - Implements checks-effects-interactions pattern
   - Has emergency withdrawal functionality (owner only)
   - Validates all external calls

### Example Integration
```javascript
// JavaScript/TypeScript example
const amountIn = ethers.parseEther("100");
const deadline = Math.floor(Date.now() / 1000) + 1200; // 20 minutes

// 1. Get expected output
const [expectedOutput, , minOutput] = await router.getExpectedOutput(tokenA.address, tokenB.address, amountIn);

// 2. Approve router
await tokenA.approve(router.address, amountIn);

// 3. Execute swap
await router.swapExactTokensForTokens(
    tokenA.address,
    tokenB.address,
    amountIn,
    minOutput,
    deadline
);
```
