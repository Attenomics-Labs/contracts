// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BondingCurve {
    // ======================
    //     Configuration
    // ======================
    /// @dev The ERC20 token (CreatorToken) managed by this contract.
    address public creatorToken;

    /// @dev The address to which protocol fees are sent.
    address public protocolFeeAddress;

    /// @dev Fee percentages in basis points (parts per 10,000).
    ///      0.5% fee on buys, 1% on sells.
    uint256 public buyFeePercent = 50;   // 0.5%
    uint256 public sellFeePercent = 100; // 1%
    uint256 public constant feePrecision = 10000;

    /// @dev Total ETH fees collected over time.
    uint256 public lifetimeProtocolFees;

    // ======================
    //  Parameters & Factors
    // ======================
    /**
     * We do a simple linear bonding curve:
     *   cost(S,A) = A*BASE_PRICE + SLOPE*( S*A + A*(A-1)/2 )
     *
     * But we do normalization to avoid overflow:
     *   1) S and A are divided by NORMALIZER (1e9).
     *   2) We multiply final cost by (1 ether / SCALING_FACTOR).
     */
    uint256 public constant NORMALIZER = 1e9;     
    uint256 public constant SCALING_FACTOR = 1e8; // tweak as desired
    
    // Choose any “smallish” base and slope here
    // so that after normalization we get a nicely scaled price.
    uint256 public constant BASE_PRICE = 1e5;  // adjustable
    uint256 public constant SLOPE      = 1e5;  // adjustable

    // ======================
    //      Constructor
    // ======================
    /**
     * @param _creatorToken The ERC20 token address (pre-funded with tokens to be sold).
     * @param _protocolFeeAddress The address to which protocol fees will be sent.
     */
    constructor(address _creatorToken, address _protocolFeeAddress) payable {
        require(_creatorToken != address(0), "Invalid token address");
        require(_protocolFeeAddress != address(0), "Invalid fee address");

        creatorToken = _creatorToken;
        protocolFeeAddress = _protocolFeeAddress;

        // If deployer sends ETH on deployment, treat it as an initial buy.
        if (msg.value > 0) {
            _initialBuy(msg.sender, msg.value);
        }
    }

    // ======================
    //   Pricing Functions
    // ======================
    /**
     * @notice Computes the total cost for buying `amount` tokens starting at supply `supply`,
     *         using a linear bonding curve.
     *
     *  1) Normalize S and A by dividing by 1e9.
     *  2) cost = A*BASE_PRICE + SLOPE( S*A + A(A-1)/2 ).
     *  3) Then multiply cost by (1 ether / SCALING_FACTOR) to get final price in wei.
     *
     * This keeps numbers from exploding and avoids overflows.
     */
    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        // Step 1: normalize
        uint256 normSupply = supply / NORMALIZER;
        uint256 normAmount = amount / NORMALIZER;

        // Step 2: linear cost in “arbitrary units”
        // costUnits = normAmount*BASE_PRICE + SLOPE*(normSupply*normAmount + normAmount*(normAmount-1)/2)
        uint256 costUnits = normAmount * BASE_PRICE
            + SLOPE * (
                normSupply * normAmount
                + (normAmount * (normAmount - 1)) / 2
            );

        // Step 3: scale to wei
        // finalCost = costUnits * (1 ether / SCALING_FACTOR)
        // which is the same as (costUnits * 1 ether)/SCALING_FACTOR
        return (costUnits * 1 ether) / SCALING_FACTOR;
    }

    /// @dev The raw buy price (no fees) for `amount` tokens at current supply.
    function getBuyPrice(uint256 amount) public view returns (uint256) {
        uint256 supply = ERC20(creatorToken).balanceOf(address(this));
        return getPrice(supply, amount);
    }

    /// @dev The raw sell price (no fees) for `amount` tokens at current supply.
    function getSellPrice(uint256 amount) public view returns (uint256) {
        uint256 supply = ERC20(creatorToken).balanceOf(address(this));
        require(supply >= amount, "Insufficient supply");
        return getPrice(supply - amount, amount);
    }

    /// @dev The buy price plus the 0.5% fee.
    function getBuyPriceAfterFees(uint256 amount) public view returns (uint256) {
        uint256 baseCost = getBuyPrice(amount);
        uint256 fee = (baseCost * buyFeePercent) / feePrecision;
        return baseCost + fee;
    }

    /// @dev The sell price minus the 1% fee.
    function getSellPriceAfterFees(uint256 amount) public view returns (uint256) {
        uint256 baseCost = getSellPrice(amount);
        uint256 fee = (baseCost * sellFeePercent) / feePrecision;
        return baseCost - fee;
    }

    // ======================
    //     Buy / Sell
    // ======================
    /**
     * @notice Internal function that approximates how many tokens can be bought with `ethAmount`
     *         (including the 0.5% fee) via binary search.
     */
    function _initialBuy(address buyer, uint256 ethAmount) internal {
        uint256 low = 0;
        uint256 high = (ethAmount / 1e9) * 2; // rough upper bound
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
        require(tokensToBuy > 0, "Insufficient ETH for initial tokens");

        uint256 totalPrice = getBuyPriceAfterFees(tokensToBuy);
        uint256 fee = (getBuyPrice(tokensToBuy) * buyFeePercent) / feePrecision;
        lifetimeProtocolFees += fee;

        // Transfer tokens to buyer
        require(ERC20(creatorToken).transfer(buyer, tokensToBuy), "Transfer failed");

        // Refund surplus ETH (if any)
        uint256 refund = ethAmount - totalPrice;
        if (refund > 0) {
            payable(buyer).transfer(refund);
        }
    }

    /**
     * @notice Buys `amount` tokens from the bonding curve.
     *         Caller must send >= getBuyPriceAfterFees(amount) in ETH.
     */
    function buy(uint256 amount) external payable {
        uint256 cost = getBuyPriceAfterFees(amount);
        require(msg.value >= cost, "Insufficient ETH for buy");

        // Accumulate fee
        uint256 fee = (getBuyPrice(amount) * buyFeePercent) / feePrecision;
        lifetimeProtocolFees += fee;

        // Transfer tokens
        require(ERC20(creatorToken).transfer(msg.sender, amount), "Transfer failed");

        // Refund leftover ETH
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }
    }

    /**
     * @notice Sells `amount` tokens back to the bonding curve.
     *         The contract must have enough ETH to pay getSellPriceAfterFees(amount).
     */
    function sell(uint256 amount) external {
        ERC20 token = ERC20(creatorToken);
        require(token.balanceOf(msg.sender) >= amount, "Insufficient token balance");

        // Transfer tokens from seller
        require(token.transferFrom(msg.sender, address(this), amount), "transferFrom failed");

        // Payout
        uint256 rawSellPrice = getSellPrice(amount);
        uint256 fee = (rawSellPrice * sellFeePercent) / feePrecision;
        uint256 netSellPrice = rawSellPrice - fee;
        lifetimeProtocolFees += fee;

        require(address(this).balance >= netSellPrice, "Not enough ETH in curve");
        payable(msg.sender).transfer(netSellPrice);
    }

    // ======================
    //   Other Functionality
    // ======================
    /**
     * @notice Provide additional liquidity by depositing CreatorToken into the contract.
     */
    function provideLiquidity(uint256 amount) external {
        require(
            ERC20(creatorToken).transferFrom(msg.sender, address(this), amount),
            "transferFrom failed"
        );
    }

    /**
     * @notice Allows the protocol fee address to withdraw accumulated ETH fees.
     */
    function withdrawFees() external {
        require(msg.sender == protocolFeeAddress, "Only fee address can withdraw");
        uint256 bal = address(this).balance;
        require(bal > 0, "No ETH to withdraw");
        payable(protocolFeeAddress).transfer(bal);
    }

    /// @dev Fallback to receive ETH (e.g. from sells).
    receive() external payable {}
}
