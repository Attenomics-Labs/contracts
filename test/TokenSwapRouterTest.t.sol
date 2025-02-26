// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TokenSwapRouter.sol";
import "./MockBondingCurve.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock token implementation
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Mock entry point contract
contract MockEntryPoint {
    mapping(address => address) public getBondingCurveByToken;

    function setMapping(address token, address curve) external {
        getBondingCurveByToken[token] = curve;
    }
}

contract TokenSwapRouterTest is Test {
    TokenSwapRouter public router;
    MockEntryPoint public entryPoint;
    MockToken public tokenA;
    MockToken public tokenB;
    MockBondingCurve public curveA;
    MockBondingCurve public curveB;
    address public feeCollector;
    address public user;

    function setUp() public {
        // Setup addresses
        feeCollector = address(0x123);
        user = address(0x456);

        // Deploy mock contracts
        entryPoint = new MockEntryPoint();
        tokenA = new MockToken("Token A", "TKNA");
        tokenB = new MockToken("Token B", "TKNB");

        // Fund user address
        vm.deal(user, 100 ether);

        // Deploy bonding curves with some ETH
        curveA = new MockBondingCurve{value: 10 ether}(address(tokenA), feeCollector);
        curveB = new MockBondingCurve{value: 10 ether}(address(tokenB), feeCollector);

        // Mint tokens to curves
        tokenA.mint(address(curveA), 1_000_000 * 1e18);
        tokenB.mint(address(curveB), 1_000_000 * 1e18);

        // Setup token-to-curve mappings
        entryPoint.setMapping(address(tokenA), address(curveA));
        entryPoint.setMapping(address(tokenB), address(curveB));

        // Deploy the router
        router = new TokenSwapRouter(feeCollector, address(entryPoint));
    }

    function testGetExpectedOutput() public {
        (uint256 expectedOutput, uint256 ethValue, uint256 minOutput) =
            router.getExpectedOutput(address(tokenA), address(tokenB), 1000 * 1e18);

        // The expected output should be non-zero
        assertTrue(expectedOutput > 0);
        assertTrue(ethValue > 0);
        assertTrue(minOutput > 0);

        // minOutput should be less than expectedOutput due to slippage
        assertTrue(minOutput < expectedOutput);
    }

    function testSwapExactTokensForTokens() public {
        uint256 swapAmount = 100 * 1e18;

        // Buy tokenA from curve for the user
        vm.startPrank(user);
        curveA.buy{value: 5 ether}(swapAmount);

        // Approve router to spend tokenA
        tokenA.approve(address(router), swapAmount);

        // Need to also approve the bonding curve to spend from the router
        vm.stopPrank();
        vm.prank(address(router));
        tokenA.approve(address(curveA), swapAmount);

        vm.startPrank(user);

        // Get expected output for swap
        (uint256 expectedOutput,, uint256 minOutput) =
            router.getExpectedOutput(address(tokenA), address(tokenB), swapAmount);

        // Record balances before swap
        uint256 tokenABalanceBefore = tokenA.balanceOf(user);
        uint256 tokenBBalanceBefore = tokenB.balanceOf(user);

        // Make sure curves have enough ETH
        vm.deal(address(curveA), 10 ether);
        vm.deal(address(curveB), 10 ether);

        // Execute swap
        router.swapExactTokensForTokens(
            address(tokenA), address(tokenB), swapAmount, minOutput, block.timestamp + 1 hours
        );

        // Verify balances after swap
        assertEq(tokenA.balanceOf(user), tokenABalanceBefore - swapAmount);
        assertTrue(tokenB.balanceOf(user) > tokenBBalanceBefore);
        assertTrue(tokenB.balanceOf(user) >= minOutput);

        vm.stopPrank();
    }

    function testFailSwapAfterDeadline() public {
        uint256 swapAmount = 100 * 1e18;

        // Buy tokenA from curve for the user
        vm.startPrank(user);
        curveA.buy{value: 1 ether}(swapAmount);

        // Approve router to spend tokenA
        tokenA.approve(address(router), swapAmount);

        // Get expected output for swap
        (,, uint256 minOutput) = router.getExpectedOutput(address(tokenA), address(tokenB), swapAmount);

        // Warp to future time
        vm.warp(block.timestamp + 2 hours);

        // Execute swap with deadline in the past
        router.swapExactTokensForTokens(
            address(tokenA), address(tokenB), swapAmount, minOutput, block.timestamp - 1 hours
        );

        vm.stopPrank();
    }

    function testFailSwapWithHighSlippage() public {
        uint256 swapAmount = 100 * 1e18;

        // Buy tokenA from curve for the user
        vm.startPrank(user);
        curveA.buy{value: 1 ether}(swapAmount);

        // Approve router to spend tokenA
        tokenA.approve(address(router), swapAmount);

        // Set an unrealistically high min output
        uint256 tooHighMinOutput = 1000 * 1e18;

        // Execute swap with too high min output
        router.swapExactTokensForTokens(
            address(tokenA), address(tokenB), swapAmount, tooHighMinOutput, block.timestamp + 1 hours
        );

        vm.stopPrank();
    }

    function testFailSwapSameToken() public {
        uint256 swapAmount = 100 * 1e18;

        vm.startPrank(user);

        // Try to swap token for itself
        router.swapExactTokensForTokens(address(tokenA), address(tokenA), swapAmount, 0, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function testFailSwapZeroAmount() public {
        vm.startPrank(user);

        // Try to swap zero tokens
        router.swapExactTokensForTokens(address(tokenA), address(tokenB), 0, 0, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function testEmergencyWithdraw() public {
        // Send some ETH to the router
        vm.deal(address(router), 1 ether);

        // Send some tokens to the router
        tokenA.mint(address(router), 1000 * 1e18);

        // Record initial balances
        uint256 ownerEthBefore = address(this).balance;
        uint256 ownerTokenBefore = tokenA.balanceOf(address(this));

        // Emergency withdraw ETH
        router.emergencyWithdraw(address(0));

        // Emergency withdraw tokens
        router.emergencyWithdraw(address(tokenA));

        // Verify balances
        assertEq(address(this).balance, ownerEthBefore + 1 ether);
        assertEq(tokenA.balanceOf(address(this)), ownerTokenBefore + 1000 * 1e18);
    }

    function testFailUnauthorizedEmergencyWithdraw() public {
        vm.prank(user);
        router.emergencyWithdraw(address(0));
    }

    // Helper function to receive ETH
    receive() external payable {}
}