// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Use named imports to reduce bytecode size
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {CreatorToken} from "./CreatorToken.sol";
import {GasliteDrop} from "./GasliteDrop.sol";

// Use custom errors instead of strings to save gas and reduce size
error NonTransferableNFT();
error HandleAlreadyUsed();
error AIAgentNotAllowed();
error InvalidGasliteDropAddress();
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
    // mapping(address => uint256) public tokenIdByCreatorToken;

    // Mapping from hashed Twitter/X handle to NFT tokenId.
    mapping(bytes32 => uint256) public tokenIdByHandle;

    uint256 public nextTokenId;

    address public gasliteDropAddress;

    // Mapping of allowed AI agents.
    mapping(address => bool) public allowedAIAgents;

    event AIAgentUpdated(address agent, bool allowed);
    event CreatorTokenDeployed(
        address indexed creator,
        address tokenAddress,
        bytes32 handle,
        uint256 tokenId
    );

    constructor(address _gasliteDropAddress) ERC721("AttenomicsCreator", "ACNFT") Ownable(msg.sender) {
        if (_gasliteDropAddress == address(0)) revert InvalidGasliteDropAddress();
        gasliteDropAddress = _gasliteDropAddress;
    }

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
     * @param configData Packed configuration parameters as bytes. This data encodes the CreatorToken.TokenConfig struct.
     * @param distributorConfigData Packed distributor configuration data (for CreatorTokenSupporter).
     * @param vaultConfigData Packed vault configuration data (for SelfTokenVault).
     * @param name Name for the CreatorToken (used for both the NFT and ERC20 token).
     * @param symbol Symbol for the CreatorToken.
     * @param nftMetadataURI Metadata URI for the NFT (should include details like token contract address, creator info, etc).
     */
    function deployCreatorToken(
        bytes memory configData,
        bytes memory distributorConfigData,
        bytes memory vaultConfigData,
        string memory name,
        string memory symbol,
        string memory nftMetadataURI
    ) external {
        CreatorToken.TokenConfig memory config = abi.decode(configData, (CreatorToken.TokenConfig));
        if (creatorTokenByHandle[config.handle] != address(0)) revert HandleAlreadyUsed();
        if (!allowedAIAgents[config.aiAgent]) revert AIAgentNotAllowed();

        address creator = msg.sender;

        // Deploy a new CreatorToken contract, passing the packed configuration data.
        CreatorToken token = new CreatorToken(
            name,
            symbol,
            configData,
            distributorConfigData,
            vaultConfigData,
            creator,
            gasliteDropAddress
        );

        // Store the vault and supporter addresses
        creatorTokenByHandle[config.handle] = address(token);
        tokenIdByHandle[config.handle] = nextTokenId;

        // Mint the NFT to the creator. This NFT is non-transferable.
        _safeMint(creator, nextTokenId);
        _setTokenURI(nextTokenId, nftMetadataURI);

        emit CreatorTokenDeployed(creator, address(token), config.handle, nextTokenId);
        nextTokenId++;
    }

    function approve(address, uint256) public pure override(ERC721, IERC721) {
        revert NonTransferableNFT();
    }

    function setApprovalForAll(address, bool) public pure override(ERC721, IERC721) {
        revert NonTransferableNFT();
    }

    function getHandleHash(string memory username) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(username));
    }


     function totalSupply() public view returns (uint256) {
        return nextTokenId;
    }
}