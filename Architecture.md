# Protocol

![Architecture](./media/Contract_Architecture.png)

The protocol’s architecture is divided into three main sections:

1. **EntryPoint**
2. **Creator Token**
3. **Token Economy**

---

## 1. EntryPoint

**Purpose:**
- Acts as a single, reliable onboarding entry point for creators.
- Maintains a registry mapping a hashed Twitter/X handle to the deployed Creator Token contract.
- Stores information about the supported AI agents that token creators can use for token distribution.
- Is implemented as an NFT contract that deploys Creator Token contracts as NFTs, providing a fraud‑proof record.
- Contains the required metadata for each Creator Token NFT so that any user can raise a fraud proof. This metadata includes:
  1. A deterministic, queryable, decentralized storage URL where all the data is stored (ideally an API endpoint in the format: `attenomics/creator/hash_of_twitter`).
  2. The creator's social profiles used to track community engagement.
  3. The creator's link tree (e.g., Instagram, Telegram, etc.).
  4. Community information (Title, Vision, Description).
  5. Details about the token distribution (Community, Self, and Market) including specifics such as the number of days for community distribution, vesting details for self tokens, and whether any initial liquidity was provided for the market.
- In the future, ownership could potentially be transferred in a more literal sense in v2.

**Benefits:**
- Enables any creator to easily deploy their token contract.
- Allows the protocol to update or manage the list of supported AI agents.
- Provides a unified integration point for the frontend.

---

## 2. Creator Token

**Overview:**
- Deployed as an ERC20 contract, the Creator Token is registered by the EntryPoint contract in the form of an NFT.
- The Creator Token contract further deploys three separate contracts (detailed in the Token Economy section).
- It serves as a standard ERC20 token and does not store any additional metadata; all metadata is maintained by the EntryPoint NFT.
- For creator token i would like to go with Efficient ByteCode20.sol for token Contract in future but for MVP its not important

**Key Features:**
- **Integrated Sub‑Contracts:**  
  Points to three sub‑contracts (detailed below in the Token Economy section):
  - **x – SelfTokenVault**
  - **y – Bonding Curve**
  - **z – Distributor Contract**

---

## 3. Token Economy

The Token Economy is modular and comprises three separate contracts, each responsible for a different aspect of token distribution and market liquidity.

### 3.1 SelfTokenVault

**Purpose:**
- Holds the creator’s personal token allocation (x%).

**Features:**
- Stores the designated x% of tokens until the creator withdraws them.
- Provides secure withdrawal functionality for the creator.

---

### 3.2 Bonding Curve

**Purpose:**
- Facilitates immediate market liquidity by making tokens available for free-market trading.

**Features:**
- Holds the market supply (y% of tokens).
- Enables users to buy and sell tokens via a bonding curve mechanism.
- Provides transparency by exposing details about the deployed bonding curve.

---

### 3.3 Distributor Contract

**Purpose:**
- Manages the controlled, time‑based distribution of tokens (z%).

**Features:**
- Holds the distributor allocation (z% of tokens) for scheduled distribution.
- Implements logic to distribute tokens over a predetermined number of days (e.g., if there are _N_ days and 1M tokens, then `1M/N` tokens are distributed per day).
- Is managed by the designated AI agent, ensuring that the distribution is automated and reliable.

---

## Summary

- **EntryPoint:**  
  Acts as an NFT-based factory and registry. It allows creators to deploy a Creator Token contract while maintaining a secure, immutable record (via a non-transferable NFT) of each deployment. It also manages a registry of supported AI agents and stores all critical metadata for fraud-proofing.

- **Creator Token:**  
  Functions as an ERC20 token that further deploys the underlying Token Economy contracts. It does not store any additional metadata—the EntryPoint handles all metadata storage and recordkeeping.

- **Token Economy:**  
  Comprises three distinct contracts:
  - **SelfTokenVault (3.1):** For holding the creator’s own tokens.
  - **Bonding Curve (3.2):** For immediate market liquidity and trading.
  - **Distributor Contract (3.3):** For time‑based token distribution managed by an AI agent.

This modular architecture ensures transparency, fraud-proofing, and efficient token distribution while providing a single, unified entry point for creators.
