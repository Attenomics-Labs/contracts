// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/console.sol";

/**
 * @title Linear Bonding Curve (with logs) 
 * 
 * Key Adjustments:
 *  1) SCALING_FACTOR = 1e12 (was 1e8)
 *  2) BASE_PRICE = 1e3, SLOPE = 1e3 (were 1e5)
 *
 * This drastically lowers final prices when supply and amounts are large.
 */
contract BondingCurve {
    // ======================
    //     Configuration
    // ======================
    address public creatorToken;
    address public protocolFeeAddress;

    // Fee configuration (basis points)
    uint256 public buyFeePercent = 50;   // 0.5%
    uint256 public sellFeePercent = 100; // 1%
    uint256 public constant feePrecision = 10000;

    // Track ETH fees collected
    uint256 public lifetimeProtocolFees;

    // ======================
    //   Bonding Parameters
    // ======================
    /**
     * We normalize the token supply/amount by dividing by NORMALIZER (1e9).
     * If your token supply is extremely large, you can increase it to 1e12.
     */
    uint256 public constant NORMALIZER = 1e12;

    /**
     * We multiply the final cost by (1 ether / SCALING_FACTOR).
     * Increasing from 1e8 to 1e12 reduces the final price by an  extra factor of 10,000.
     */
    uint256 public constant SCALING_FACTOR = 1e28;

    /**
     * Base price & slope, reduced from 1e5 to 1e3 to produce lower costUnits.
     */
    uint256 public constant BASE_PRICE = 1e2;
    uint256 public constant SLOPE      = 1e3;

    // ======================
    //      Constructor
    // ======================
    constructor(address _creatorToken, address _protocolFeeAddress) payable {
        require(_creatorToken != address(0), "Invalid token address");
        require(_protocolFeeAddress != address(0), "Invalid fee address");
        creatorToken = _creatorToken;
        protocolFeeAddress = _protocolFeeAddress;

        // If contract is deployed with ETH, treat it as an initial buy.
        if (msg.value > 0) {
            _initialBuy(msg.sender, msg.value);
        }
    }

    // ======================
    //   Pricing Functions
    // ======================
    /**
     * @notice Computes the linear cost:
     *   1) Normalize supply & amount by dividing by NORMALIZER.
     *   2) costUnits = A*BASE_PRICE + SLOPE*(S*A + A*(A-1)/2).
     *   3) finalWei = costUnits * (1 ether / SCALING_FACTOR).
     */
    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        // 1) normalize
        uint256 normSupply = supply / NORMALIZER;
        uint256 normAmount = amount / NORMALIZER;

        // 2) linear cost in “units”
        uint256 costUnits = normAmount * BASE_PRICE
            + SLOPE * (
                normSupply * normAmount
                + (normAmount * (normAmount - 1)) / 2
            );

        // 3) scale to wei
        return (costUnits * 1 ether) / SCALING_FACTOR;
    }

    /// @dev Buy price (no fees).
    function getBuyPrice(uint256 amount) public view returns (uint256) {
        uint256 supply = ERC20(creatorToken).balanceOf(address(this));
        return getPrice(supply, amount);
    }

    /// @dev Sell price (no fees).
    function getSellPrice(uint256 amount) public view returns (uint256) {
        uint256 supply = ERC20(creatorToken).balanceOf(address(this));
        require(supply >= amount, "Insufficient supply");
        return getPrice(supply - amount, amount);
    }

    /// @dev Buy price + 0.5% fee.
    function getBuyPriceAfterFees(uint256 amount) public view returns (uint256) {
        uint256 rawPrice = getBuyPrice(amount);
        uint256 fee = (rawPrice * buyFeePercent) / feePrecision;
        return rawPrice + fee;
    }

    /// @dev Sell price - 1% fee.
    function getSellPriceAfterFees(uint256 amount) public view returns (uint256) {
        uint256 rawPrice = getSellPrice(amount);
        uint256 fee = (rawPrice * sellFeePercent) / feePrecision;
        return rawPrice - fee;
    }

    // ======================
    //     Buy / Sell
    // ======================

    /**
     * @notice Approximates how many tokens can be purchased with `ethAmount` (including the 0.5% fee)
     *         using a binary search.
     */
    function _initialBuy(address buyer, uint256 ethAmount) internal {
        uint256 low = 0;
        uint256 high = (ethAmount / 1e9) * 2;
        for (uint256 i = 0; i < 20; i++) {
            uint256 mid = (low + high) / 2;
            uint256 testPrice = getBuyPriceAfterFees(mid);
            if (testPrice <= ethAmount) {
                low = mid;
            } else {
                high = mid;
            }
        }
        uint256 tokensToBuy = low;
        require(tokensToBuy > 0, "No tokens for initial buy");

        // compute final cost and fee
        uint256 rawPrice = getBuyPrice(tokensToBuy);
        uint256 totalCost = getBuyPriceAfterFees(tokensToBuy);
        uint256 fee = totalCost - rawPrice;
        lifetimeProtocolFees += fee;

        // LOG some data for debugging
        console.log("=== Initial Buy ===");
        console.log("Buyer:", buyer);
        console.log("Tokens to buy:", tokensToBuy);
        console.log("Raw price:", rawPrice);
        console.log("Fee:", fee);
        console.log("Total cost:", totalCost);

        // transfer tokens
        ERC20(creatorToken).transfer(buyer, tokensToBuy);

        // refund leftover
        uint256 refund = ethAmount - totalCost;
        if (refund > 0) {
            payable(buyer).transfer(refund);
        }
    }

    /**
     * @notice Buys `amount` tokens from the curve.
     */
    function buy(uint256 amount) external payable {
        uint256 cost = getBuyPriceAfterFees(amount);
        require(msg.value >= cost, "Insufficient ETH for buy");

        uint256 rawPrice = getBuyPrice(amount);
        uint256 fee = cost - rawPrice;
        lifetimeProtocolFees += fee;

        // LOG the buy details
        console.log("=== Buy ===");
        console.log("Buyer:", msg.sender);
        console.log("Amount:", amount );
        console.log("Raw price:", rawPrice);
        console.log("Fee:", fee);
        console.log("Total cost:", cost / 1e10, "ETH");

        // Transfer tokens
        require(ERC20(creatorToken).transfer(msg.sender, amount), "Transfer failed");

        // Refund leftover
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }
    }

    /**
     * @notice Sells `amount` tokens back to the curve.
     */
    function sell(uint256 amount) external {
        ERC20 token = ERC20(creatorToken);
        require(token.balanceOf(msg.sender) >= amount, "Not enough tokens");

        require(token.transferFrom(msg.sender, address(this), amount), "transferFrom failed");

        uint256 rawSellPrice = getSellPrice(amount);
        uint256 fee = (rawSellPrice * sellFeePercent) / feePrecision;
        uint256 netSellPrice = rawSellPrice - fee;
        lifetimeProtocolFees += fee;

        // Ensure enough ETH
        require(address(this).balance >= netSellPrice, "Not enough ETH in curve");

        // LOG the sell details
        console.log("=== Sell ===");
        console.log("Seller:", msg.sender);
        console.log("Amount:", amount);
        console.log("Raw price:", rawSellPrice);
        console.log("Fee:", fee);
        console.log("Net payout:", netSellPrice / 1e10 , "ETH" );

        // Payout
        payable(msg.sender).transfer(netSellPrice);
    }

    // ======================
    //   Liquidity & Fees
    // ======================
    function provideLiquidity(uint256 amount) external {
        require(ERC20(creatorToken).transferFrom(msg.sender, address(this), amount), "transferFrom failed");
    }

    function withdrawFees() external {
        require(msg.sender == protocolFeeAddress, "Not fee address");
        uint256 bal = address(this).balance;
        require(bal > 0, "No ETH to withdraw");
        payable(protocolFeeAddress).transfer(bal);
    }

    receive() external payable {}
    fallback() external payable {}
}
