// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/CreatorToken.sol";
import "../src/SelfTokenVault.sol";
import "../src/BondingCurve.sol";
import "../src/CreatorTokenSupporter.sol";
import "../src/GasliteDrop.sol";

contract CreatorTokenTest is Test {
    CreatorToken public token;
    address public creator;
    address public aiAgent;
    bytes32 public handle;
    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 1e18;

    // Events to test
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        creator = address(this);
        aiAgent = address(0x123);
        handle = keccak256(abi.encodePacked("test_creator"));

        // Create token config
        CreatorToken.TokenConfig memory config = CreatorToken.TokenConfig({
            totalSupply: TOTAL_SUPPLY,
            selfPercent: 10,
            marketPercent: 80,
            supporterPercent: 10,
            handle: handle,
            aiAgent: aiAgent
        });

        // Create distributor config
        CreatorTokenSupporter.DistributorConfig memory distributorConfig = CreatorTokenSupporter.DistributorConfig({
            dailyDripAmount: 1000 * 1e18,
            dripInterval: 1 days,
            totalDays: 100
        });

        // Create vault config
        SelfTokenVault.VaultConfig memory vaultConfig = SelfTokenVault.VaultConfig({
            dripPercentage: 10,
            dripInterval: 30 days,
            lockTime: 180 days,
            lockedPercentage: 80
        });

        // Deploy GasliteDrop
        address gasliteDrop = address(new GasliteDrop());

        // Deploy token with configs
        token = new CreatorToken(
            "Test Token",
            "TEST",
            abi.encode(config),
            abi.encode(distributorConfig),
            abi.encode(vaultConfig),
            creator,
            gasliteDrop
        );
    }

    function testInitialSetup() public view {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TEST");
        assertEq(token.decimals(), 18);
        assertEq(token.totalERC20Supply(), TOTAL_SUPPLY);
        assertEq(token.creator(), creator);
        assertEq(token.aiAgent(), aiAgent);
        assertEq(token.handle(), handle);
    }

    function testTokenDistribution() public view {
        // Calculate expected amounts
        uint256 selfTokens = (TOTAL_SUPPLY * 10) / 100;
        uint256 marketTokens = (TOTAL_SUPPLY * 80) / 100;
        uint256 supporterTokens = (TOTAL_SUPPLY * 10) / 100;

        // Check balances
        assertEq(token.balanceOf(token.selfTokenVault()), selfTokens);
        assertEq(token.balanceOf(token.bondingCurve()), marketTokens);
        assertEq(token.balanceOf(token.supporterContract()), supporterTokens);
    }

    function testContractAddresses() public view {
        assertTrue(token.selfTokenVault() != address(0));
        assertTrue(token.bondingCurve() != address(0));
        assertTrue(token.supporterContract() != address(0));
    }

    function testGetterFunctions() public view {
        assertEq(token.getVaultAddress(), token.selfTokenVault());
        assertEq(token.getSupporterAddress(), token.supporterContract());
    }

    function testFailZeroAddressCreator() public {
        CreatorToken.TokenConfig memory config = CreatorToken.TokenConfig({
            totalSupply: TOTAL_SUPPLY,
            selfPercent: 10,
            marketPercent: 80,
            supporterPercent: 10,
            handle: handle,
            aiAgent: aiAgent
        });

        // Should fail when creator is address(0)
        new CreatorToken("Test Token", "TEST", abi.encode(config), "", "", address(0), address(0));
    }

    function testFailInvalidPercentages() public {
        CreatorToken.TokenConfig memory config = CreatorToken.TokenConfig({
            totalSupply: TOTAL_SUPPLY,
            selfPercent: 20,
            marketPercent: 85, // Total > 100%
            supporterPercent: 10,
            handle: handle,
            aiAgent: aiAgent
        });

        new CreatorToken("MyTestToken-Subtle", "TEST", abi.encode(config), "", "", creator, address(0));
    }
}
