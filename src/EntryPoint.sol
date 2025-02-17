// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin contracts (make sure these are available in your project)
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SelfTokenVault.sol";
import "./CreatorToken.sol";


/// @title EntryPoint
/// @notice Factory contract that deploys a new CreatorToken contract using the provided parameters.
contract EntryPoint {
    // Store addresses of all deployed CreatorToken contracts.
    address[] public deployedTokens;

    event TokenDeployed(address indexed tokenAddress, address indexed creator);

    /// @notice Deploys a new CreatorToken contract.
    /// @param name Token name.
    /// @param symbol Token symbol.
    /// @param totalSupply Total token supply.
    /// @param selfPercentage Percentage for self tokens.
    /// @param marketPercentage Percentage for market tokens.
    /// @param contractPercentage Percentage for reserved tokens.
    /// @param marketAddr Address to receive market tokens.
    /// @return The address of the newly deployed CreatorToken contract.
    function deployToken(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint8 selfPercentage,
        uint8 marketPercentage,
        uint8 contractPercentage,
        address marketAddr
    ) external returns (address) {
        // Deploy a new CreatorToken, passing msg.sender as the creator.
        CreatorToken token = new CreatorToken(
            name,
            symbol,
            totalSupply,
            selfPercentage,
            marketPercentage,
            contractPercentage,
            marketAddr,
            msg.sender
        );
        deployedTokens.push(address(token));
        emit TokenDeployed(address(token), msg.sender);
        return address(token);
    }
}
