// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/console.sol";

/**
 * @title BondingCurve (Single-Counter Model)
 *
 * In this implementation:
 * - The available tokens for sale are defined by the ERC20 token balance held by this contract.
 * - purchaseMarketSupply is the effective "sold" supply used for pricing, which starts at 0.
 *
 * When buying:
 *   • The cost is computed using getPrice(purchaseMarketSupply, amount).
 *   • purchaseMarketSupply is increased by the purchased amount.
 *
 * When selling:
 *   • The payout is computed using getPrice(purchaseMarketSupply - amount, amount).
 *   • purchaseMarketSupply is decreased by the sold amount.
 *
 * This decouples the pricing mechanism from the actual token balance.
 *
 * Additionally, we log the ETH amounts and their dollar equivalent using a conversion factor of 1 ETH = $3000.
 */
contract BondingCurve {
    // ======================
    //     Configuration
    // ======================
    address public creatorToken;
    address public protocolFeeAddress;

    // Fee configuration (basis points)
    uint256 public buyFeePercent = 50; // 0.5%
    uint256 public sellFeePercent = 100; // 1%
    uint256 public constant feePrecision = 10000;

    // Track ETH fees collected
    uint256 public lifetimeProtocolFees;

    // ======================
    //   Bonding Parameters
    // ======================
    /**
     * NORMALIZER: Normalizes token amounts.
     * SCALING_FACTOR: Scales the final cost.
     * BASE_PRICE & SLOPE: Parameters for the linear bonding curve.
     */
    uint256 public constant NORMALIZER = 1e12;
    uint256 public constant SCALING_FACTOR = 1e28;
    uint256 public constant BASE_PRICE = 1e2;
    uint256 public constant SLOPE = 1e3;

    /**
     * purchaseMarketSupply represents the effective supply used for pricing.
     * It starts at 0 and increases as tokens are bought via the bonding curve.
     */
    uint256 public purchaseMarketSupply;

    // ======================
    //      Constructor
    // ======================
    constructor(address _creatorToken, address _protocolFeeAddress) payable {
        require(_creatorToken != address(0), "Invalid token address");
        require(_protocolFeeAddress != address(0), "Invalid fee address");
        creatorToken = _creatorToken;
        protocolFeeAddress = _protocolFeeAddress;
        purchaseMarketSupply = 0;

        // If deployed with ETH, perform an initial buy.
        if (msg.value > 0) {
            _initialBuy(msg.sender, msg.value);
        }
    }

    // ======================
    //   Pricing Functions
    // ======================
    /**
     * @notice Calculates the cost to add `amount` tokens on top of an effective supply.
     * The formula is:
     *   costUnits = normAmount * BASE_PRICE + SLOPE * (normSupply * normAmount + (normAmount*(normAmount-1))/2)
     * where normSupply and normAmount are normalized by NORMALIZER.
     * The final cost (in wei) is: (costUnits * 1 ether) / SCALING_FACTOR.
     */
    function getPrice(
        uint256 effectiveSupply,
        uint256 amount
    ) public pure returns (uint256) {
        uint256 normSupply = effectiveSupply / NORMALIZER;
        uint256 normAmount = amount / NORMALIZER;
        uint256 costUnits = normAmount *
            BASE_PRICE +
            SLOPE *
            (normSupply * normAmount + (normAmount * (normAmount - 1)) / 2);
        return (costUnits * 1 ether) / SCALING_FACTOR;
    }

    /// @dev Returns the buy price (without fees) based on the current effective supply.
    function getBuyPrice(uint256 amount) public view returns (uint256) {
        return getPrice(purchaseMarketSupply, amount);
    }

    /// @dev Returns the sell price (without fees) based on reducing the effective supply.
    function getSellPrice(uint256 amount) public view returns (uint256) {
        require(
            purchaseMarketSupply >= amount,
            "Insufficient effective supply"
        );
        return getPrice(purchaseMarketSupply - amount, amount);
    }

    /// @dev Returns the buy price including a fee.
    function getBuyPriceAfterFees(
        uint256 amount
    ) public view returns (uint256) {
        uint256 rawPrice = getBuyPrice(amount);
        uint256 fee = (rawPrice * buyFeePercent) / feePrecision;
        return rawPrice + fee;
    }

    /// @dev Returns the sell price after subtracting a fee.
    function getSellPriceAfterFees(
        uint256 amount
    ) public view returns (uint256) {
        uint256 rawPrice = getSellPrice(amount);
        uint256 fee = (rawPrice * sellFeePercent) / feePrecision;
        return rawPrice - fee;
    }

function getTokensForEth(uint256 ethAmount) public view returns (uint256) {
    uint256 low = 0;
    uint256 high = (ethAmount * NORMALIZER) / BASE_PRICE; // Set a reasonable upper bound
    for (uint256 i = 0; i < 20; i++) {
        uint256 mid = (low + high) / 2;
        uint256 price = getBuyPriceAfterFees(mid);
        if (price <= ethAmount) {
            low = mid;
        } else {
            high = mid;
        }
    }
    return low;
}


    /**
     * @notice Calculates how many tokens need to be sold to receive the given ETH amount.
     * Uses binary search to determine the required token amount.
     */
    function getTokensToSellForEth(
        uint256 ethAmount
    ) public view returns (uint256) {
        uint256 low = 0;
        uint256 high = purchaseMarketSupply;
        for (uint256 i = 0; i < 20; i++) {
            uint256 mid = (low + high) / 2;
            uint256 price = getSellPriceAfterFees(mid);
            if (price >= ethAmount) {
                high = mid;
            } else {
                low = mid;
            }
        }
        return high;
    }

    // ======================
    //   Buy / Sell Routines
    // ======================
    /**
     * @notice Approximates the number of tokens that can be purchased with `ethAmount`
     *         via a binary search, then executes the initial buy.
     */
    function _initialBuy(address buyer, uint256 ethAmount) internal {
        uint256 low = 0;
        // Use a rough high-bound estimate
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
        require(
            tokensToBuy <= ERC20(creatorToken).balanceOf(address(this)),
            "Not enough tokens available"
        );

        uint256 rawPrice = getBuyPrice(tokensToBuy);
        uint256 totalCost = getBuyPriceAfterFees(tokensToBuy);
        uint256 fee = totalCost - rawPrice;
        lifetimeProtocolFees += fee;

        console.log("=== Initial Buy ===");
        console.log("Buyer:", buyer);
        console.log("Tokens to buy:", tokensToBuy);
        console.log("Raw price (wei):", rawPrice);
        console.log("Fee (wei):", fee);
        console.log("Total cost (wei):", totalCost);
        // Calculate and log dollar equivalent assuming 1 ETH = $3000.
        uint256 totalCostDollars = (totalCost * 3000) / 1e18;
        console.log("Total cost ($):", totalCostDollars);

        // Update effective supply and transfer tokens.
        purchaseMarketSupply += tokensToBuy;
        require(
            ERC20(creatorToken).transfer(buyer, tokensToBuy),
            "Transfer failed"
        );

        // Refund any leftover ETH.
        uint256 refund = ethAmount - totalCost;
        if (refund > 0) {
            payable(buyer).transfer(refund);
        }
    }

    /**
     * @notice Buys `amount` tokens.
     * Requirements:
     *   - The amount must be greater than 0.
     *   - The ERC20 token balance of the contract (available tokens) must be at least `amount`.
     *   - The ETH sent must cover the cost (including fee).
     */
    function buy(uint256 amount) external payable returns (uint256) {
        require(amount > 0, "Amount must be > 0");
        require(
            amount <= ERC20(creatorToken).balanceOf(address(this)),
            "Not enough tokens available"
        );

        uint256 cost = getBuyPriceAfterFees(amount);
        require(msg.value >= cost, "Insufficient ETH for buy");

        uint256 rawPrice = getBuyPrice(amount);
        uint256 fee = cost - rawPrice;
        lifetimeProtocolFees += fee;

        console.log("=== Buy ===");
        console.log("Buyer:", msg.sender);
        console.log("Amount:", amount);
        console.log("Raw price (wei):", rawPrice);
        console.log("Fee (wei):", fee);
        console.log("Total cost (wei):", cost);
        // Log dollar equivalent.
        uint256 costDollars = (cost * 3000) / 1e18;
        console.log("Total cost ($):", costDollars);

        // Increase effective supply for pricing.
        purchaseMarketSupply += amount;

        // Transfer tokens from this contract to the buyer.
        require(
            ERC20(creatorToken).transfer(msg.sender, amount),
            "Token transfer failed"
        );

        // Refund any extra ETH.
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        return cost;
    }

    /**
     * @notice Sells `amount` tokens back to the curve.
     * Requirements:
     *   - The seller must hold at least `amount` tokens.
     *   - The effective supply must be at least `amount`.
     *
     * On sell, the effective supply is reduced and the tokens are returned to the contract.
     */
    function sell(uint256 amount) external returns (uint256) {
        require(amount > 0, "Amount must be > 0");
        ERC20 token = ERC20(creatorToken);
        require(
            token.balanceOf(msg.sender) >= amount,
            "Not enough tokens to sell"
        );
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        uint256 rawSellPrice = getSellPrice(amount);
        uint256 fee = (rawSellPrice * sellFeePercent) / feePrecision;
        uint256 netSellPrice = rawSellPrice - fee;
        lifetimeProtocolFees += fee;

        console.log("=== Sell ===");
        console.log("Seller:", msg.sender);
        console.log("Amount:", amount);
        console.log("Raw price (wei):", rawSellPrice);
        console.log("Fee (wei):", fee);
        console.log("Net payout (wei):", netSellPrice);
        // Log dollar equivalent.
        uint256 netSellPriceDollars = (netSellPrice * 3000) / 1e18;
        console.log("Net payout ($):", netSellPriceDollars);

        // Decrease the effective supply.
        require(purchaseMarketSupply >= amount, "Effective supply underflow");
        purchaseMarketSupply -= amount;

        require(
            address(this).balance >= netSellPrice,
            "Not enough ETH in curve"
        );
        payable(msg.sender).transfer(netSellPrice);

        return netSellPrice;
    }

    // ======================
    //   Liquidity & Fees
    // ======================
    /**
     * @notice Allows anyone to deposit tokens to the bonding curve (increasing available tokens).
     */
    function provideLiquidity(uint256 amount) external {
        require(
            ERC20(creatorToken).transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );
    }

    /**
     * @notice Withdraws collected ETH fees to the protocol fee address.
     */
    function withdrawFees() external {
        require(msg.sender == protocolFeeAddress, "Caller is not fee address");
        uint256 bal = address(this).balance;
        require(bal > 0, "No ETH to withdraw");
        payable(protocolFeeAddress).transfer(bal);
    }

    // Accept ETH deposits.
    receive() external payable {}

    fallback() external payable {}
}
