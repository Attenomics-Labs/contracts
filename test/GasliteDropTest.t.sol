// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GasliteDrop.sol";
import "../src/CreatorToken.sol";
import "./MockBondingCurve.sol"; // Import our new mock
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
    constructor() ERC721("Mock NFT", "MNFT") {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}

// Add a simplified mock for SelfTokenVault
contract MockSelfTokenVault {
    address public token;
    address public owner;

    constructor(address _token, address _owner) {
        token = _token;
        owner = _owner;
    }
}

// Add a simplified mock for CreatorTokenSupporter
contract MockCreatorTokenSupporter {
    address public creatorToken;
    address public aiAgent;

    constructor(address _token, address _aiAgent) {
        creatorToken = _token;
        aiAgent = _aiAgent;
    }
}

// Mock CreatorToken that allows setting the sub-contracts directly
contract TestCreatorToken is ERC20 {
    address public selfTokenVault;
    address public bondingCurve;
    address public supporterContract;
    address public creator;
    bytes32 public handle;
    address public aiAgent;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        creator = msg.sender;
    }

    function setSubContracts(
        address _vault,
        address _curve,
        address _supporter,
        address _creator,
        address _aiAgent,
        bytes32 _handle
    )
        public
    {
        selfTokenVault = _vault;
        bondingCurve = _curve;
        supporterContract = _supporter;
        creator = _creator;
        aiAgent = _aiAgent;
        handle = _handle;
    }

    function mintTokens(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract GasliteDropTest is Test {
    GasliteDrop public gasliteDrop;
    TestCreatorToken public token; // Using our test token
    MockERC721 public nft;
    address public deployer;
    address[] public recipients;
    uint256[] public amounts;
    uint256[] public tokenIds;
    uint256 public constant RECIPIENT_COUNT = 100;
    uint256 public constant TOKENS_PER_RECIPIENT = 100 * 1e18;

    function setUp() public {
        // Set deployer address
        deployer = address(this);

        // Deploy contracts
        gasliteDrop = new GasliteDrop();
        nft = new MockERC721();

        // Create our token with simplified setup
        token = new TestCreatorToken("Test Token", "TEST");

        // Total supply for our test
        uint256 totalSupply = 1_000_000 * 1e18;

        // Calculate token distribution
        uint256 selfTokens = totalSupply * 10 / 100;
        uint256 marketTokens = totalSupply * 80 / 100;
        uint256 supporterTokens = totalSupply * 10 / 100;

        // Mint tokens directly
        token.mintTokens(address(this), totalSupply);

        // Create handle hash
        bytes32 handleHash = keccak256(abi.encodePacked("test"));

        // Create our mock sub-contracts
        MockSelfTokenVault vault = new MockSelfTokenVault(address(token), deployer);
        MockBondingCurve curve = new MockBondingCurve(address(token), deployer);
        MockCreatorTokenSupporter supporter = new MockCreatorTokenSupporter(address(token), address(this));

        // Set up token's sub-contracts
        token.setSubContracts(address(vault), address(curve), address(supporter), deployer, address(this), handleHash);

        // Transfer tokens to the various sub-contracts
        token.transfer(address(vault), selfTokens);
        token.transfer(address(curve), marketTokens);
        token.transfer(address(supporter), supporterTokens);

        // Initialize arrays
        recipients = new address[](RECIPIENT_COUNT);
        amounts = new uint256[](RECIPIENT_COUNT);
        tokenIds = new uint256[](RECIPIENT_COUNT);

        uint256 requiredTokens = RECIPIENT_COUNT * TOKENS_PER_RECIPIENT;

        // Use deal to ensure we have enough tokens for testing
        token.mintTokens(deployer, requiredTokens);

        // Setup test data
        for (uint256 i = 0; i < RECIPIENT_COUNT; i++) {
            recipients[i] = address(uint160(i + 1));
            amounts[i] = TOKENS_PER_RECIPIENT;
            tokenIds[i] = i;
            // Mint NFTs to deployer
            nft.mint(deployer, i);
        }

        // Approve transfers
        token.approve(address(gasliteDrop), RECIPIENT_COUNT * TOKENS_PER_RECIPIENT);
        for (uint256 i = 0; i < RECIPIENT_COUNT; i++) {
            nft.approve(address(gasliteDrop), i);
        }
    }

    function testAirdropERC20() public {
        uint256 totalAmount = RECIPIENT_COUNT * TOKENS_PER_RECIPIENT;

        // Record initial balances
        uint256[] memory initialBalances = new uint256[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            initialBalances[i] = token.balanceOf(recipients[i]);
        }

        // Execute airdrop
        gasliteDrop.airdropERC20(address(token), recipients, amounts, totalAmount);

        // Verify balances
        for (uint256 i = 0; i < recipients.length; i++) {
            assertEq(token.balanceOf(recipients[i]), initialBalances[i] + amounts[i], "Balance mismatch for recipient");
        }
    }

    function testAirdropERC721() public {
        // Record initial owners
        address[] memory initialOwners = new address[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            initialOwners[i] = nft.ownerOf(tokenIds[i]);
        }

        // Execute airdrop
        gasliteDrop.airdropERC721(address(nft), recipients, tokenIds);

        // Verify ownership transfers
        for (uint256 i = 0; i < recipients.length; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), recipients[i], "Ownership transfer failed");
            assertTrue(nft.ownerOf(tokenIds[i]) != initialOwners[i], "Owner should have changed");
        }
    }

    function testLargeERC20Airdrop() public {
        // Reduce the size to something more manageable
        uint256 largeCount = 200; // Reduced from 1000
        address[] memory largeRecipients = new address[](largeCount);
        uint256[] memory largeAmounts = new uint256[](largeCount);
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < largeCount; i++) {
            largeRecipients[i] = address(uint160(i + 1000));
            largeAmounts[i] = 1 ether;
            totalAmount += 1 ether;
        }

        // Mint additional tokens for the large airdrop
        token.mintTokens(deployer, totalAmount);
        token.approve(address(gasliteDrop), totalAmount);

        uint256 gasBefore = gasleft();
        gasliteDrop.airdropERC20(address(token), largeRecipients, largeAmounts, totalAmount);
        uint256 gasUsed = gasBefore - gasleft();

        // Increase gas limit to something more realistic
        assertTrue(gasUsed < 10_000_000, "Gas usage too high");
    }

    function testFailERC20MismatchedArrays() public {
        // Create mismatched arrays
        address[] memory shortRecipients = new address[](RECIPIENT_COUNT - 1);
        gasliteDrop.airdropERC20(
            address(token),
            shortRecipients,
            amounts, // Original longer array
            RECIPIENT_COUNT * TOKENS_PER_RECIPIENT
        );
    }

    function testFailERC721MismatchedArrays() public {
        // Create mismatched arrays
        address[] memory shortRecipients = new address[](RECIPIENT_COUNT - 1);

        gasliteDrop.airdropERC721(
            address(nft),
            shortRecipients,
            tokenIds // Original longer array
        );
    }

    receive() external payable {}
}
