// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CreatorToken.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title AttenomicsCreatorEntryPoint
 * @notice This contract acts as a single, reliable onboarding entry point.
 *         It is an ERC721 (non-transferable NFT) contract that mints an NFT for each
 *         deployed CreatorToken contract. The NFT metadata (stored by this contract)
 *         can include details such as the token contract address, creator information,
 *         and other data required for fraud-proofing. Additionally, the contract maintains
 *         mappings from a hashed Twitter/X handle to both the deployed CreatorToken address
 *         and the associated NFT tokenId.
 */
contract AttenomicsCreatorEntryPoint is ERC721URIStorage, Ownable {
    // Mapping from hashed Twitter/X handle to deployed CreatorToken contract address.
    mapping(bytes32 => address) public creatorTokenByHandle;

    // Mapping from CreatorToken contract address to NFT tokenId.
    mapping(address => uint256) public tokenIdByCreatorToken;

    // Mapping from hashed Twitter/X handle to NFT tokenId.
    mapping(bytes32 => uint256) public tokenIdByHandle;

    // Counter for NFT tokenIds.
    uint256 public nextTokenId;

    // Mapping of allowed AI agents.
    mapping(address => bool) public allowedAIAgents;

    event AIAgentUpdated(address agent, bool allowed);
    event CreatorTokenDeployed(
        address indexed creator,
        address tokenAddress,
        bytes32 handle,
        uint256 tokenId
    );

    constructor() ERC721("AttenomicsCreator", "ACNFT") Ownable(msg.sender) {}

    /**
     * @notice Allows the owner (protocol admin) to register or unregister an AI agent.
     * @param agent The AI agent's address.
     * @param allowed True if the agent is allowed; false otherwise.
     */
    function setAIAgent(address agent, bool allowed) external onlyOwner {
        allowedAIAgents[agent] = allowed;
        emit AIAgentUpdated(agent, allowed);
    }

    /**
     * @notice Deploys a new CreatorToken contract and mints a non-transferable NFT representing it.
     * @param handle Hashed Twitter/X handle (a unique identifier for the creator).
     * @param name Name for the CreatorToken (used for both the NFT and ERC20 token).
     * @param symbol Symbol for the CreatorToken.
     * @param totalSupply Total ERC20 token supply.
     * @param selfPercent Percentage allocated to the SelfTokenVault (x).
     * @param marketPercent Percentage allocated to the BondingCurve (y).
     * @param supporterPercent Percentage allocated to the Distributor (z).
     * @param aiAgent Address designated as the AI agent (owner of the distributor contract).
     * @param nftMetadataURI Metadata URI for the NFT (should include details like token contract address, creator info, etc).
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
        string memory nftMetadataURI,
        address creator
    ) external {
        require(
            creatorTokenByHandle[handle] == address(0),
            "Handle already used"
        );
        // Enforce allowed AI agents.
        require(allowedAIAgents[aiAgent], "AI agent not allowed");

        // Deploy a new CreatorToken contract.
        CreatorToken token = new CreatorToken(
            name,
            symbol,
            totalSupply,
            selfPercent,
            marketPercent,
            supporterPercent,
            creator, // @dev is this a vulnerability? where anyone can deploy a token for someone else? should be msg.sender?
            handle,
            aiAgent
        );

        // Store the deployed CreatorToken contract.
        creatorTokenByHandle[handle] = address(token);
        tokenIdByCreatorToken[address(token)] = nextTokenId;
        tokenIdByHandle[handle] = nextTokenId;

        // Mint the NFT to the creator. This NFT is non-transferable.
        _safeMint(msg.sender, nextTokenId);
        _setTokenURI(nextTokenId, nftMetadataURI);

        emit CreatorTokenDeployed(
            msg.sender,
            address(token),
            handle,
            nextTokenId
        );
        nextTokenId++;
    }

    // Override approve to disable approvals.
    function approve(address, uint256) public pure override(ERC721, IERC721) {
        revert("Non-transferable NFT");
    }

    // Override setApprovalForAll to disable approvals.
    function setApprovalForAll(
        address,
        bool
    ) public pure override(ERC721, IERC721) {
        revert("Non-transferable NFT");
    }

    function getHandleHash(
        string memory username
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(username));
    }
}
