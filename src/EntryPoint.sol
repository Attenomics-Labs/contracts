// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin contracts (make sure these are available in your project)
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SelfTokenVault.sol";
import "./CreatorToken.sol";

/* 
  ─────────────────────────────────────────────
   1) ENTRY POINT (Factory + Registry)
  ─────────────────────────────────────────────
*/


contract EntryPoint is Ownable {
    // Optional: track which addresses are valid AI agents
    mapping(address => bool) public allowedAIAgents;

    // Maps a hashed Twitter/X handle to the deployed CreatorToken contract
    mapping(bytes32 => address) public creatorTokenByHandle;

    event AIAgentUpdated(address agent, bool allowed);
    event CreatorTokenDeployed(address indexed creator, address tokenAddress, bytes32 handle);

    constructor() Ownable(msg.sender){}
    /**
     * @notice Allows the owner to register/unregister an AI agent.
     * @param agent The AI agent’s address.
     * @param allowed True if allowed, false if removed.
     */
    function setAIAgent(address agent, bool allowed) external onlyOwner {
        allowedAIAgents[agent] = allowed;
        emit AIAgentUpdated(agent, allowed);
    }

    /**
     * @notice Deploy a new CreatorToken contract, which will internally deploy:
     *         - SelfTokenVault
     *         - BondingCurve
     *         - CreatorTokenSupporter
     *
     * @param handle Hashed Twitter/X handle (unique ID for the creator).
     * @param name Name for both the NFT and ERC20 token.
     * @param symbol Symbol for both the NFT and ERC20 token.
     * @param totalSupply Total ERC20 supply.
     * @param selfPercent x% to SelfTokenVault.
     * @param marketPercent y% to BondingCurve.
     * @param supporterPercent z% to CreatorTokenSupporter.
     * @param aiAgent Address designated as the AI agent (owner of the supporter contract).
     * @param nftMetadataURI URI for the NFT metadata (tokenId = 1).
     */
    function deployCreatorToken(
        bytes32 handle,
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint8 selfPercent,
        uint8 marketPercent,
        uint8 supporterPercent,
        address aiAgent,
        string memory nftMetadataURI
    ) external {
        // Make sure this handle has not already been used
        require(creatorTokenByHandle[handle] == address(0), "Handle already used");
        // Optional check if the AI agent is allowed
        // require(allowedAIAgents[aiAgent], "AI agent not allowed");

        // Deploy CreatorToken
        CreatorToken token = new CreatorToken(
            name,
            symbol,
            totalSupply,
            selfPercent,
            marketPercent,
            supporterPercent,
            msg.sender,       // The creator
            aiAgent         // The AI agent
        );

        // Register in the mapping
        creatorTokenByHandle[handle] = address(token);

        // Emit an event for indexing
        emit CreatorTokenDeployed(msg.sender, address(token), handle);
    }
}