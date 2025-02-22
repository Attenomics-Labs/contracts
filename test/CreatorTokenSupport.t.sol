    // SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/CreatorTokenSupporter.sol";
import "../src/CreatorToken.sol";
import "../src/GasliteDrop.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract CreatorTokenSupporterTest is Test {
    using ECDSA for bytes32;

    CreatorTokenSupporter public supporter;
    CreatorToken public token;
    GasliteDrop public gasliteDrop;
    address public aiAgent;
    uint256 public aiAgentPrivateKey;
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;

    event DistributionExecuted(bytes32 indexed dataHash, address indexed executor);

    function setUp() public {
        // Generate AI agent address and private key
        aiAgentPrivateKey = 0x123;
        aiAgent = vm.addr(aiAgentPrivateKey);

        // Deploy GasliteDrop
        gasliteDrop = new GasliteDrop();

        // Create distributor config
        CreatorTokenSupporter.DistributorConfig memory distributorConfig = CreatorTokenSupporter.DistributorConfig({
            dailyDripAmount: 1000 * 1e18,
            dripInterval: 1 days,
            totalDays: 100
        });

        // Create proper vault config
        SelfTokenVault.VaultConfig memory vaultConfig = SelfTokenVault.VaultConfig({
            dripPercentage: 10,
            dripInterval: 30 days,
            lockTime: 180 days,
            lockedPercentage: 80
        });

        // Deploy creator token with configs
        CreatorToken.TokenConfig memory config = CreatorToken.TokenConfig({
            totalSupply: INITIAL_SUPPLY,
            selfPercent: 10,
            marketPercent: 80,
            supporterPercent: 10,
            handle: keccak256(abi.encodePacked("test")),
            aiAgent: aiAgent
        });

        token = new CreatorToken(
            "Test Token",
            "TEST",
            abi.encode(config),
            abi.encode(distributorConfig),
            abi.encode(vaultConfig),
            address(this),
            address(gasliteDrop)
        );

        // Get the supporter contract address that was created by CreatorToken
        supporter = CreatorTokenSupporter(token.supporterContract());
    }

    function testInitialSetup() public view {
        assertEq(supporter.creatorToken(), address(token));
        assertEq(supporter.aiAgent(), aiAgent);
        assertEq(supporter.owner(), aiAgent);
        assertEq(supporter.gasLiteDropAddress(), address(gasliteDrop));
    }

    function testDirectDistribution() public {
        address[] memory recipients = new address[](2);
        recipients[0] = address(0x1);
        recipients[1] = address(0x2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 * 1e18;
        amounts[1] = 200 * 1e18;

        uint256 totalAmount = 300 * 1e18;

        // First approve gasliteDrop to spend tokens from supporter
        vm.startPrank(address(supporter));
        token.approve(address(gasliteDrop), type(uint256).max);
        vm.stopPrank();

        // Now perform distribution as aiAgent
        vm.prank(aiAgent);
        supporter.distribute(recipients, amounts, totalAmount);

        assertEq(token.balanceOf(address(0x1)), 100 * 1e18);
        assertEq(token.balanceOf(address(0x2)), 200 * 1e18);
        assertEq(supporter.totalDistributed(), totalAmount);
    }

    function testSignedDistribution() public {
        // Prepare distribution data
        address[] memory recipients = new address[](2);
        recipients[0] = address(0x1);
        recipients[1] = address(0x2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 * 1e18;
        amounts[1] = 200 * 1e18;

        uint256 totalAmount = 300 * 1e18;

        CreatorTokenSupporter.DistributionData memory data =
            CreatorTokenSupporter.DistributionData({recipients: recipients, amounts: amounts, totalAmount: totalAmount});

        // Generate signature
        bytes32 dataHash = keccak256(abi.encode(recipients, amounts, totalAmount));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(dataHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aiAgentPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Make sure GasliteDrop has approval
        vm.prank(address(supporter));
        token.approve(address(gasliteDrop), type(uint256).max);

        // Execute distribution
        supporter.distributeWithData(abi.encode(data), signature);

        assertEq(token.balanceOf(address(0x1)), 100 * 1e18);
        assertEq(token.balanceOf(address(0x2)), 200 * 1e18);
        assertEq(supporter.totalDistributed(), totalAmount);
    }

    function testFailInvalidSignature() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(0x1);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 * 1e18;

        CreatorTokenSupporter.DistributionData memory data =
            CreatorTokenSupporter.DistributionData({recipients: recipients, amounts: amounts, totalAmount: 100 * 1e18});

        // Use wrong private key for signature
        uint256 wrongPrivateKey = 0x456;
        bytes32 dataHash = keccak256(abi.encode(recipients, amounts, 100 * 1e18));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(dataHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        supporter.distributeWithData(abi.encode(data), signature);
    }

    function testFailUnauthorizedDirectDistribution() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(0x1);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 * 1e18;

        vm.prank(address(0xdead));
        supporter.distribute(recipients, amounts, 100 * 1e18);
    }

    function testFailDoubleSpendHash() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(0x1);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 * 1e18;

        CreatorTokenSupporter.DistributionData memory data =
            CreatorTokenSupporter.DistributionData({recipients: recipients, amounts: amounts, totalAmount: 100 * 1e18});

        bytes32 dataHash = keccak256(abi.encode(recipients, amounts, 100 * 1e18));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(dataHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aiAgentPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // First distribution succeeds
        supporter.distributeWithData(abi.encode(data), signature);

        // Second distribution with same hash fails
        supporter.distributeWithData(abi.encode(data), signature);
    }
}
