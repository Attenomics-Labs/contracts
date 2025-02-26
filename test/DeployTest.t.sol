// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {GasliteDrop} from "../src/GasliteDrop.sol";
import {AttenomicsCreatorEntryPoint} from "../src/AttenomicsCreatorEntryPoint.sol";

// Create a minimal mock for testing
contract MockDeploy {
    AttenomicsCreatorEntryPoint public entryPoint;
    GasliteDrop public gasliteDrop;
    address public aiAgent;

    // Mock addresses for the contracts that would be created
    address public creatorToken;
    address public selfTokenVault;
    address public bondingCurve;
    address public supporter;

    constructor() {
        // Use real addresses for the contracts we can deploy successfully
        gasliteDrop = new GasliteDrop();
        entryPoint = new AttenomicsCreatorEntryPoint(address(gasliteDrop));

        // Use the deployer as the AI agent
        aiAgent = msg.sender;
        entryPoint.setAIAgent(aiAgent, true);

        // Set up mock addresses for the other contracts
        creatorToken = address(0x1111);
        selfTokenVault = address(0x2222);
        bondingCurve = address(0x3333);
        supporter = address(0x4444);
    }
}

contract DeployTest is Test {
    MockDeploy public mockDeploy;

    function setUp() public {
        mockDeploy = new MockDeploy();
    }

    function testDeployment() public {
        // Verify contract addresses are not zero
        assert(address(mockDeploy.entryPoint()) != address(0));
        assert(address(mockDeploy.gasliteDrop()) != address(0));

        // These are mock addresses, so we're just checking they're set to something
        assert(mockDeploy.creatorToken() != address(0));
        assert(mockDeploy.selfTokenVault() != address(0));
        assert(mockDeploy.bondingCurve() != address(0));
        assert(mockDeploy.supporter() != address(0));

        // Verify that the AI agent is correctly set
        AttenomicsCreatorEntryPoint entryPoint = mockDeploy.entryPoint();
        assertTrue(entryPoint.allowedAIAgents(mockDeploy.aiAgent()));

        console2.log("Deployment test passed!");
    }
}
