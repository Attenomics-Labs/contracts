// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BondingCurve.sol";
import "./AttenomicsCreatorEntryPoint.sol";
import "forge-std/console.sol";

/**
 * @title TokenSwapRouter
 * @notice Enables swaps between any two creator tokens using their bonding curves
 * @dev Uses a two-step process: Token A -> ETH -> Token B
 */
contract TokenSwapRouter is Ownable, ReentrancyGuard {
    // Protocol fee configuration (can be adjusted)
    uint256 public constant ROUTER_FEE = 10; // 0.1% additional fee
    uint256 public constant FEE_PRECISION = 10000;
    uint256 public constant MAX_SLIPPAGE = 1000; // 10% max slippage

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
        ethValue = curveA.getSellPrice(amountIn);
        
        // Apply router fee
        uint256 routerFeeAmount = (ethValue * ROUTER_FEE) / FEE_PRECISION;
        ethValue -= routerFeeAmount;

        // Use the correct function from BondingCurve contract
        expectedOutput = curveB.getBuyPrice(ethValue);
        
        // Calculate minimum output with max slippage
        minOutput = (expectedOutput * (FEE_PRECISION - MAX_SLIPPAGE)) / FEE_PRECISION;
    }

    /**
     * @notice Executes a token-to-token swap with deadline and slippage protection
     */
    function swapExactTokensForTokens(
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) external nonReentrant {
        // Step 1: Initial checks
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (tokenA == tokenB) revert InvalidToken();
        if (amountIn == 0) revert InvalidToken();

        // Step 2: Get bonding curves
        BondingCurve curveA = BondingCurve(payable(getBondingCurveForToken(tokenA)));
        BondingCurve curveB = BondingCurve(payable(getBondingCurveForToken(tokenB)));

        // Get initial state
        uint256 initialETHBalance = address(this).balance;
        
        // Transfer tokenA from user
        if (!ERC20(tokenA).transferFrom(msg.sender, address(this), amountIn)) {
            revert TokenTransferFailed();
        }

        try curveA.sell(amountIn) returns (uint256 ethReceived) {
            // Apply router fee
            uint256 routerFeeAmount = (ethReceived * ROUTER_FEE) / FEE_PRECISION;
            uint256 buyAmount = ethReceived - routerFeeAmount;

            if (routerFeeAmount > 0) {
                payable(feeCollector).transfer(routerFeeAmount);
            }

            try curveB.buy{value: buyAmount}(buyAmount) returns (uint256 amountOut) {
                // Verify minimum output
                if (amountOut < minAmountOut) revert ExcessiveSlippage();

                // Transfer tokenB to user
                if (!ERC20(tokenB).transfer(msg.sender, amountOut)) {
                    revert TokenTransferFailed();
                }

                emit TokenSwap(msg.sender, tokenA, tokenB, amountIn, amountOut, ethReceived);
            } catch {
                // If buy fails, return ETH to user
                payable(msg.sender).transfer(buyAmount);
                emit SwapError(msg.sender, tokenA, tokenB, amountIn, "Buy operation failed");
                revert SwapOperationFailed();
            }
        } catch {
            // If sell fails, return tokenA to user
            if (!ERC20(tokenA).transfer(msg.sender, amountIn)) {
                revert TokenTransferFailed();
            }
            emit SwapError(msg.sender, tokenA, tokenB, amountIn, "Sell operation failed");
            revert SwapOperationFailed();
        }
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
        address bondingCurve = entryPoint.getBondingCurveByToken(token);
        if (bondingCurve == address(0)) revert InvalidToken();
        
        // Check if the bonding curve has tokens, but don't revert if we're in the deployment phase
        // This is determined by checking if the token has any supply yet
        if (ERC20(token).totalSupply() > 0 && ERC20(token).balanceOf(bondingCurve) == 0) {
            revert InvalidToken();
        }
        
        return bondingCurve;
    }

    // Allow contract to receive ETH
    receive() external payable {}
} 