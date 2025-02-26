// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock CreatorToken for testing
contract MockCreatorToken is ERC20 {
    address public selfTokenVault;
    address public bondingCurve;
    address public supporterContract;
    address public creator;
    address public aiAgent;
    bytes32 public handle;
    uint256 public totalERC20Supply;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        address _creator,
        address _aiAgent,
        bytes32 _handle
    )
        ERC20(_name, _symbol)
    {
        creator = _creator;
        aiAgent = _aiAgent;
        handle = _handle;
        totalERC20Supply = _totalSupply;

        // Create mock subcontracts
        selfTokenVault = address(new MockContract());
        bondingCurve = address(new MockContract());
        supporterContract = address(new MockContract());

        // Calculate token distribution
        uint256 selfTokens = (_totalSupply * 10) / 100;
        uint256 marketTokens = (_totalSupply * 80) / 100;
        uint256 supporterTokens = (_totalSupply * 10) / 100;

        // Mint tokens to subcontracts
        _mint(selfTokenVault, selfTokens);
        _mint(bondingCurve, marketTokens);
        _mint(supporterContract, supporterTokens);
    }

    function getVaultAddress() public view returns (address) {
        return selfTokenVault;
    }

    function getSupporterAddress() public view returns (address) {
        return supporterContract;
    }
}

// Simple mock contract
contract MockContract {
// Empty contract to create addresses
}

contract CreatorTokenTest is Test {
    MockCreatorToken public token;
    address public creator;
    address public aiAgent;
    bytes32 public handle;
    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 1e18;

    function setUp() public {
        creator = address(this);
        aiAgent = address(0x123);
        handle = keccak256(abi.encodePacked("test_creator"));

        // Deploy the mock token
        token = new MockCreatorToken("Test Token", "TEST", TOTAL_SUPPLY, creator, aiAgent, handle);
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
}
