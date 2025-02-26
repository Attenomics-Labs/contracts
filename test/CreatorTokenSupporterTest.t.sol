// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/CreatorTokenSupporter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// Simple mock token
contract MockToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Simple mock GasliteDrop
contract MockGasliteDrop {
    function airdropERC20(
        address token,
        address[] memory recipients,
        uint256[] memory amounts,
        uint256 totalAmount
    )
        external
    {
        require(recipients.length == amounts.length, "Arrays must be same length");

        // Transfer tokens from caller to recipients
        for (uint256 i = 0; i < recipients.length; i++) {
            ERC20(token).transferFrom(msg.sender, recipients[i], amounts[i]);
        }
    }
}

contract CreatorTokenSupporterTest is Test {
    using ECDSA for bytes32;

    CreatorTokenSupporter public supporter;
    MockToken public token;
    MockGasliteDrop public gasliteDrop;
    address public aiAgent;
    uint256 public aiAgentPrivateKey;
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;

    event DistributionExecuted(bytes32 indexed dataHash, address indexed executor);

    function setUp() public {
        // Generate AI agent address and private key
        aiAgentPrivateKey = 0x123;
        aiAgent = vm.addr(aiAgentPrivateKey);

        // Deploy mock contracts
        token = new MockToken();
        gasliteDrop = new MockGasliteDrop();

        // Create distributor config
        CreatorTokenSupporter.DistributorConfig memory distributorConfig = CreatorTokenSupporter.DistributorConfig({
            dailyDripAmount: 1000 * 1e18,
            dripInterval: 1 days,
            totalDays: 100
        });

        // Deploy supporter contract directly
        supporter =
            new CreatorTokenSupporter(address(token), aiAgent, abi.encode(distributorConfig), address(gasliteDrop));

        // Mint tokens to the supporter contract
        uint256 supporterAmount = INITIAL_SUPPLY * 10 / 100; // 10% of supply
        token.mint(address(supporter), supporterAmount);
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

        // Make sure GasliteDrop has approval
        vm.prank(address(supporter));
        token.approve(address(gasliteDrop), type(uint256).max);

        // First distribution succeeds
        supporter.distributeWithData(abi.encode(data), signature);

        // Second distribution with same hash fails
        supporter.distributeWithData(abi.encode(data), signature);
    }
}
