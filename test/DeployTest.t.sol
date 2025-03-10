// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {AttenomicsCreatorEntryPoint} from "../src/AttenomicsCreatorEntryPoint.sol";
import {CreatorToken} from "../src/CreatorToken.sol";
import {SelfTokenVault} from "../src/SelfTokenVault.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {GasliteDrop} from "../src/GasliteDrop.sol";
import {CreatorTokenSupporter} from "../src/CreatorTokenSupporter.sol";

contract DeployTest is Test {
    Deploy public deployScript;

    function setUp() public {
        deployScript = new Deploy();
    }

    function testDeployment() public {
        // Run the deployment script
        deployScript.run();

        // Verify contract addresses are not zero
        assert(deployScript.entryPoint() != address(0));
        assert(deployScript.creatorToken() != address(0));
        assert(deployScript.selfTokenVault() != address(0));
        assert(deployScript.bondingCurve() != address(0));
        assert(deployScript.gasliteDrop() != address(0));
        assert(deployScript.supporter() != address(0));

        // Verify that the AI agent is correctly set
        AttenomicsCreatorEntryPoint entryPoint = AttenomicsCreatorEntryPoint(deployScript.entryPoint());
        assert(entryPoint.allowedAIAgents(deployScript.aiAgent()));

        // Verify the creator token's configurations
        CreatorToken creatorToken = CreatorToken(deployScript.creatorToken());
        assertEq(creatorToken.totalSupply(), 1_000_000 * 1e18);
        assertEq(creatorToken.selfTokenVault(), deployScript.selfTokenVault());
        assertEq(creatorToken.supporterContract(), deployScript.supporter());
        assertEq(creatorToken.bondingCurve(), deployScript.bondingCurve());

        console2.log("Deployment script test passed!");
    }
}