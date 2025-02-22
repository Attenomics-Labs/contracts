// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title SelfTokenVault
 * @notice Holds the creator's tokens (x%) until they are withdrawn.
 *         Tokens are vested according to a configurable schedule—similar
 *         to VC vesting. A portion of tokens (lockedPercentage) is subject
 *         to vesting: after an initial lock period (lockTime), every dripInterval
 *         a fixed percentage (dripPercentage) of the locked tokens is released.
 *
 *         The remaining tokens (100 - lockedPercentage) are available immediately.
 *
 *         For correct vesting calculations, the owner (creator) must call initialize()
 *         once tokens have been minted to the vault.
 */
contract SelfTokenVault is Ownable {
    address public token;

    // Vault configuration struct.
    struct VaultConfig {
        uint256 dripPercentage;   // Percentage of the locked tokens to release per interval.
        uint256 dripInterval;     // Interval (in seconds) between drips.
        uint256 lockTime;         // Lock period (in seconds) before vesting starts.
        uint256 lockedPercentage; // Percentage of tokens that are subject to vesting (0-100).
    }
    
    VaultConfig public vaultConfig;

    // The initial total tokens deposited in the vault.
    uint256 public initialBalance;
    // Total tokens that have been withdrawn.
    uint256 public withdrawn;
    // The timestamp when vesting starts (typically set to contract deployment time).
    uint256 public startTime;
    // Flag to ensure initialization happens only once.
    bool public initialized;

    /**
     * @param _token The ERC20 token address.
     * @param _creator The address that will own the vault (typically the creator).
     * @param selfVaultConfig Packed configuration data encoding a VaultConfig struct.
     */
    constructor(address _token, address _creator, bytes memory selfVaultConfig) Ownable(_creator) {
        token = _token;
        // Decode the vault configuration data.
        VaultConfig memory config = abi.decode(selfVaultConfig, (VaultConfig));
        vaultConfig = config;
        // Set vesting start time to deployment time.
        startTime = block.timestamp;
    }

    /**
     * @notice Initializes the vault by recording the initial token balance.
     *         This should be called once, after tokens have been minted/transferred to this contract.
     */
    function initialize() public {
        require(!initialized, "Already initialized");
        initialBalance = ERC20(token).balanceOf(address(this));
        initialized = true;
    }

    /**
     * @notice Calculates the available token amount for withdrawal based on the vesting schedule.
     * @return The amount of tokens that can currently be withdrawn.
     */
    function availableForWithdrawal() public view returns (uint256) {
        if (!initialized) {
            return 0;
        }

        // Immediate portion is the tokens not subject to vesting.
        uint256 immediateRelease = (initialBalance * (100 - vaultConfig.lockedPercentage)) / 100;
        
        uint256 vested;
        // Vesting only starts after the lock period.
        if (block.timestamp > startTime + vaultConfig.lockTime) {
            // Calculate how many full intervals have passed since vesting began.
            uint256 intervals = (block.timestamp - (startTime + vaultConfig.lockTime)) / vaultConfig.dripInterval;
            uint256 lockedAmount = (initialBalance * vaultConfig.lockedPercentage) / 100;
            // Amount vested per interval.
            uint256 perInterval = (lockedAmount * vaultConfig.dripPercentage) / 100;
            vested = intervals * perInterval;
            if (vested > lockedAmount) {
                vested = lockedAmount;
            }
        }
        
        // Total tokens available for withdrawal.
        uint256 totalAvailable = immediateRelease + vested;
        if (totalAvailable > initialBalance) {
            totalAvailable = initialBalance;
        }
        // Subtract tokens already withdrawn.
        if (totalAvailable > withdrawn) {
            return totalAvailable - withdrawn;
        } else {
            return 0;
        }
    }

    /**
     * @notice Withdraws all tokens that are available according to the vesting schedule.
     */
    function withdraw() external onlyOwner {
        uint256 amount = availableForWithdrawal();
        require(amount > 0, "No tokens available for withdrawal");
        withdrawn += amount;
        ERC20(token).transfer(owner(), amount);
    }
}
