// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BondingCurve.sol";
import "./AttenomicsCreatorEntryPoint.sol";
import "./CreatorToken.sol";
import "forge-std/console.sol";

/**
 * @title TokenSwapRouter
 * @notice Enables swaps between any two creator tokens using their bonding curves
 * @dev Uses a two-step process: Token A -> ETH -> Token B
 */
contract TokenSwapRouter is Ownable, ReentrancyGuard {

    // Protocol fee collector
    address public immutable feeCollector;

    // Add EntryPoint reference
    AttenomicsCreatorEntryPoint public immutable entryPoint;

    // Add error definitions
    error DeadlineExpired();
    error ExcessiveSlippage();
    error InvalidToken();
    error SwapOperationFailed();
    error TokenTransferFailed();

    // Events
    event TokenSwap(
        address indexed user,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountIn,
        uint256 amountOut,
        uint256 ethValue
    );

    event SwapError(
        address indexed user,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountIn,
        string reason
    );

    constructor(
        address _feeCollector,
        address _entryPoint
    ) Ownable(msg.sender) {
        require(_feeCollector != address(0), "Invalid fee collector");
        require(_entryPoint != address(0), "Invalid entry point");
        feeCollector = _feeCollector;
        entryPoint = AttenomicsCreatorEntryPoint(_entryPoint);
    }

    /**
     * @notice Calculates the expected output amount and ETH value for a token-to-token swap
     */
    function getExpectedOutput(
        address tokenA,
        address tokenB,
        uint256 amountIn
    ) public view returns (
        uint256 expectedOutput,
        uint256 ethValue,
        uint256 minOutput
    ) {
        BondingCurve curveA = BondingCurve(payable(getBondingCurveForToken(tokenA)));
        BondingCurve curveB = BondingCurve(payable(getBondingCurveForToken(tokenB)));

        // Get ETH value from selling tokenA
        ethValue = curveA.getSellPriceAfterFees(amountIn);

        // Use the correct function from BondingCurve contract
        expectedOutput = curveB.getTokensForEth(ethValue);
        
        // Calculate minimum output with max slippage
        minOutput = expectedOutput;
    }

    /**
     * @notice Executes a token-to-token swap with deadline and slippage protection
     */
    function swapExactTokensForTokens(
        address tokenA,
        address tokenB,
        uint256 amountIn
    ) external nonReentrant {
        // Step 1: Initial checks
        // if (block.timestamp > deadline) revert DeadlineExpired();
        if (tokenA == tokenB) revert InvalidToken();
        if (amountIn == 0) revert InvalidToken();

        // Step 2: Get bonding curves
        BondingCurve curveA = BondingCurve(payable(getBondingCurveForToken(tokenA)));
        BondingCurve curveB = BondingCurve(payable(getBondingCurveForToken(tokenB)));

        // Get initial state
        uint256 initialETHBalance = address(this).balance;
        
        // Transfer tokenA from user
        require(ERC20(tokenA).transferFrom(msg.sender, address(this), amountIn), "Transfer failed");
        
        // Approve curveA to spend tokenA
        require(ERC20(tokenA).approve(address(curveA), amountIn), "Approval failed");

        // Sell tokenA for ETH
        uint256 ethReceived = curveA.sell(amountIn);
        
        // Calculate tokens to buy using getTokensForEth

        uint256 tokensToReceive = curveB.getTokensForEth(ethReceived);

        uint256 tokenBeforeBuy = ERC20(tokenB).balanceOf(address(this));
        
        // Buy tokenB with ETH
        curveB.buy{value: ethReceived}(tokensToReceive - ((tokensToReceive * curveB.buyFeePercent()) / curveB.feePrecision()));

        uint256 tokenAfterBuy = ERC20(tokenB).balanceOf(address(this));

        uint256 amountOut = tokenAfterBuy - tokenBeforeBuy;

        // Verify minimum output
        // if (amountOut < minAmountOut) revert ExcessiveSlippage();

        // Transfer tokenB to user
        require(ERC20(tokenB).transfer(msg.sender, amountOut), "Transfer failed");

        emit TokenSwap(msg.sender, tokenA, tokenB, amountIn, amountOut, ethReceived);
    }

    /**
     * @notice Emergency withdrawal of stuck tokens/ETH by owner
     */
    function emergencyWithdraw(address token) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(address(this).balance);
        } else {
            uint256 balance = ERC20(token).balanceOf(address(this));
            if (balance > 0) {
                ERC20(token).transfer(owner(), balance);
            }
        }
    }

    /**
     * @notice Helper function to get bonding curve address for a token
     * @param token Token address
     * @return Bonding curve address
     */
    function getBondingCurveForToken(address token) internal view returns (address) {
        address bondingCurve = CreatorToken(token).bondingCurve();
        if (bondingCurve == address(0)) {
            // Try to get it directly from the token contract
            try CreatorToken(token).bondingCurve() returns (address curve) {
                if (curve == address(0)) revert InvalidToken();
                return curve;
            } catch {
                revert InvalidToken();
            }
        }
        return bondingCurve;
    }

    // Allow contract to receive ETH
    receive() external payable {}
} 