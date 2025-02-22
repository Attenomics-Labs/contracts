// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AttenomicsCreatorEntryPoint.sol";
import "../src/CreatorToken.sol";

contract AttenomicsCreatorEntryPointTest is Test {
    AttenomicsCreatorEntryPoint public entryPoint;
    address public owner;
    address public aiAgent;
    bytes32 public handle;

    event AIAgentUpdated(address agent, bool allowed);
    event CreatorTokenDeployed(address indexed creator, address tokenAddress, bytes32 handle, uint256 tokenId);

    function setUp() public {
        owner = address(this);
        aiAgent = address(0x123);
        handle = keccak256(abi.encodePacked("test_creator"));

        // Deploy entry point
        entryPoint = new AttenomicsCreatorEntryPoint();

        // Set AI agent
        entryPoint.setAIAgent(aiAgent, true);
    }

    function testInitialSetup() public view {
        assertEq(entryPoint.name(), "AttenomicsCreator");
        assertEq(entryPoint.symbol(), "ACNFT");
        assertEq(entryPoint.owner(), owner);
        assertTrue(entryPoint.allowedAIAgents(aiAgent));
    }

    function testSetAIAgent() public {
        address newAgent = address(0x456);

        vm.expectEmit(true, true, true, true);
        emit AIAgentUpdated(newAgent, true);

        entryPoint.setAIAgent(newAgent, true);
        assertTrue(entryPoint.allowedAIAgents(newAgent));

        vm.expectEmit(true, true, true, true);
        emit AIAgentUpdated(newAgent, false);

        entryPoint.setAIAgent(newAgent, false);
        assertFalse(entryPoint.allowedAIAgents(newAgent));
    }

    function testFailUnauthorizedAIAgent() public {
        // Prepare config with unauthorized AI agent
        CreatorToken.TokenConfig memory config = CreatorToken.TokenConfig({
            totalSupply: 1_000_000 * 1e18,
            selfPercent: 10,
            marketPercent: 80,
            supporterPercent: 10,
            handle: handle,
            aiAgent: address(0xdead) // Unauthorized agent
        });

        entryPoint.deployCreatorToken(abi.encode(config), "", "", "Test Token", "TEST", "ipfs://test-uri");
    }

    function testFailDuplicateHandle() public {
        // First deployment
        CreatorToken.TokenConfig memory config = CreatorToken.TokenConfig({
            totalSupply: 1_000_000 * 1e18,
            selfPercent: 10,
            marketPercent: 80,
            supporterPercent: 10,
            handle: handle,
            aiAgent: aiAgent
        });

        entryPoint.deployCreatorToken(abi.encode(config), "", "", "Test Token", "TEST", "ipfs://test-uri");

        // Try to deploy with same handle
        entryPoint.deployCreatorToken(abi.encode(config), "", "", "Test Token 2", "TEST2", "ipfs://test-uri-2");
    }

    function testFailNFTTransfer() public {
        // Deploy a token to get an NFT
        CreatorToken.TokenConfig memory config = CreatorToken.TokenConfig({
            totalSupply: 1_000_000 * 1e18,
            selfPercent: 10,
            marketPercent: 80,
            supporterPercent: 10,
            handle: handle,
            aiAgent: aiAgent
        });

        entryPoint.deployCreatorToken(abi.encode(config), "", "", "Test Token", "TEST", "ipfs://test-uri");

        // Try to transfer the NFT
        entryPoint.transferFrom(address(this), address(0x123), 0);
    }

    function testGetHandleHash() public view {
        string memory username = "test_creator";
        bytes32 expectedHash = keccak256(abi.encodePacked(username));
        assertEq(entryPoint.getHandleHash(username), expectedHash);
    }

    function testFailSetAIAgentUnauthorized() public {
        vm.prank(address(0xdead));
        entryPoint.setAIAgent(address(0x456), true);
    }
}
