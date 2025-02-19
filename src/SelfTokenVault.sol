// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title SelfTokenVault
 * @notice Holds the creator’s tokens (x%) until the creator withdraws them.
 *         It decodes a packed configuration (VaultConfig) that can specify parameters
 *         such as the drip percentage, drip interval, lock time, and locked percentage.
 */
contract SelfTokenVault is Ownable {
    address public token;

    // Example vault configuration struct.
    struct VaultConfig {
        uint256 dripPercentage;   // Percentage of tokens to drip per interval.
        uint256 dripInterval;     // Interval (in seconds) between drips.
        uint256 lockTime;         // Lock period (in seconds).
        uint256 lockedPercentage; // Percentage of tokens to lock.
    }
    VaultConfig public vaultConfig;

    constructor(address _token, address _creator, bytes memory selfVaultConfig) Ownable(msg.sender) {
        token = _token;
        // Decode the vault configuration data.
        VaultConfig memory config = abi.decode(selfVaultConfig, (VaultConfig));
        vaultConfig = config;
        // Transfer ownership of the vault to the creator.
        _transferOwnership(_creator);
    }

    /**
     * @notice Withdraws all tokens from the vault to the vault owner (the creator).
     */
    function withdraw() external onlyOwner {
        uint256 balance = ERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens in vault");
        ERC20(token).transfer(owner(), balance);
    }
}
