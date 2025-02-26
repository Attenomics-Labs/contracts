// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TokenSwapRouter.sol";
import "../src/AttenomicsCreatorEntryPoint.sol";
import "../src/CreatorToken.sol";
import "../src/BondingCurve.sol";
import "../src/GasliteDrop.sol";

contract TokenSwapRouterTest is Test {
    // Contracts
    TokenSwapRouter public router;
    AttenomicsCreatorEntryPoint public entryPoint;
    GasliteDrop public gasliteDrop;
    CreatorToken public tokenA;
    CreatorToken public tokenB;

    // Test addresses
    address public creator = makeAddr("creator");
    address public user = makeAddr("user");
    address public feeCollector = makeAddr("feeCollector");
    address public aiAgent = makeAddr("aiAgent");

    function setUp() public {
        // Deploy GasliteDrop
        gasliteDrop = new GasliteDrop();

        // Deploy EntryPoint
        entryPoint = new AttenomicsCreatorEntryPoint(address(gasliteDrop));

        // Set AI agent
        vm.prank(address(this));
        entryPoint.setAIAgent(aiAgent, true);

        // Deploy Router
        router = new TokenSwapRouter(feeCollector, address(entryPoint));

        // Fund user with ETH
        vm.deal(user, 100 ether);
    }

    function testBasicSwap() public {
        // Deploy two test tokens
        vm.startPrank(creator);
        
        // Deploy TokenA
        bytes32 handleA = entryPoint.getHandleHash("TokenA");
        CreatorToken.TokenConfig memory configA = CreatorToken.TokenConfig({
            totalSupply: 1_000_000 ether,
            selfPercent: 20,
            marketPercent: 60,
            supporterPercent: 20,
            handle: handleA,
            aiAgent: aiAgent
        });

        entryPoint.deployCreatorToken(
            abi.encode(configA),
            new bytes(0), // empty distributor config
            new bytes(0), // empty vault config
            "Token A",
            "TKNA",
            "ipfs://tokenA"
        );

        // Get TokenA instance
        tokenA = CreatorToken(entryPoint.creatorTokenByHandle(handleA));

        // Deploy TokenB (similar process)
        bytes32 handleB = entryPoint.getHandleHash("TokenB");
        CreatorToken.TokenConfig memory configB = CreatorToken.TokenConfig({
            totalSupply: 1_000_000 ether,
            selfPercent: 20,
            marketPercent: 60,
            supporterPercent: 20,
            handle: handleB,
            aiAgent: aiAgent
        });

        entryPoint.deployCreatorToken(
            abi.encode(configB),
            new bytes(0),
            new bytes(0),
            "Token B",
            "TKNB",
            "ipfs://tokenB"
        );

        tokenB = CreatorToken(entryPoint.creatorTokenByHandle(handleB));
        vm.stopPrank();

        // Test basic swap functionality
        vm.startPrank(user);

        // First buy some tokenA using its bonding curve
        BondingCurve curveA = BondingCurve(payable(tokenA.bondingCurve()));
        curveA.buy{value: 1 ether}(1 ether);

        // Check user received tokens
        uint256 initialBalanceA = tokenA.balanceOf(user);
        assertGt(initialBalanceA, 0, "User should have received TokenA");

        // Approve router to spend tokenA
        tokenA.approve(address(router), initialBalanceA);

        // Get expected output
        (uint256 expectedOutput, , uint256 minOutput) = router.getExpectedOutput(
            address(tokenA),
            address(tokenB),
            initialBalanceA
        );

        // Execute swap
        router.swapExactTokensForTokens(
            address(tokenA),
            address(tokenB),
            initialBalanceA,
            minOutput,
            block.timestamp + 1 hours
        );

        // Verify swap results
        assertEq(tokenA.balanceOf(user), 0, "All TokenA should be spent");
        assertGt(tokenB.balanceOf(user), 0, "Should have received TokenB");
        assertGe(tokenB.balanceOf(user), minOutput, "Should have received at least minOutput");

        vm.stopPrank();
    }

    function testFailSwapWithExpiredDeadline() public {
        vm.startPrank(user);
        
        router.swapExactTokensForTokens(
            address(tokenA),
            address(tokenB),
            1 ether,
            0,
            block.timestamp - 1 // Expired deadline
        );

        vm.stopPrank();
    }

    receive() external payable {}
}