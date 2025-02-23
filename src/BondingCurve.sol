// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BondingCurve {
    // The ERC20 token (CreatorToken) held by this contract.
    address public creatorToken;
    // The address to which protocol fees are sent.
    address public protocolFeeAddress;
    
    // Fee percentages in basis points.
    // 0.5% fee on buy orders (50 / 10000).
    uint256 public buyFeePercent = 50;
    // 1% fee on sell orders (100 / 10000).
    uint256 public sellFeePercent = 100;
    uint256 public constant feePrecision = 10000;
    
    // Total ETH fees collected over time.
    uint256 public lifetimeProtocolFees;
    
    // Constant representing the token's 18 decimal places.
    uint256 public constant TOKEN_UNIT = 1e18;
    
    /**
     * @notice Computes the total cost for purchasing `amount` tokens starting at a given `supply`
     * using your provided sum-of-squares formula.
     *
     * IMPORTANT:
     * This function expects both `supply` and `amount` to be in whole token units
     * (i.e. already normalized by dividing by TOKEN_UNIT).
     *
     * The formula is:
     *   sum1 = (supply-1) * supply * (2*(supply-1) + 1) / 6    [if supply > 0, else 0]
     *   sum2 = (supply + amount - 1) * (supply + amount) * (2*(supply + amount - 1) + 1) / 6
     *   summation = sum2 - sum1
     *   price = (summation * 1 ether) / 16000
     */
    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : ((supply - 1) * supply * (2 * (supply - 1) + 1)) / 6;
        uint256 sum2 = (supply + amount - 1) * (supply + amount) * (2 * (supply + amount - 1) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return (summation * 1 ether) / 16000;
    }
    
    /// @notice Returns the raw buy price (without fees) for the given amount.
    function getBuyPrice(uint256 amount) public view returns (uint256) {
        // Get the raw token balance (in wei) and normalize it.
        uint256 rawSupply = ERC20(creatorToken).balanceOf(address(this));
        uint256 normSupply = rawSupply / TOKEN_UNIT;
        uint256 normAmount = amount / TOKEN_UNIT;
        return getPrice(normSupply, normAmount);
    }
    
    /// @notice Returns the raw sell price (without fees) for the given amount.
    function getSellPrice(uint256 amount) public view returns (uint256) {
        uint256 rawSupply = ERC20(creatorToken).balanceOf(address(this));
        require(rawSupply >= amount, "Insufficient supply");
        uint256 normSupply = rawSupply / TOKEN_UNIT;
        uint256 normAmount = amount / TOKEN_UNIT;
        // When selling, the effective supply is reduced by normAmount.
        return getPrice(normSupply - normAmount, normAmount);
    }
    
    /// @notice Returns the buy price after adding the 0.5% fee.
    function getBuyPriceAfterFees(uint256 amount) public view returns (uint256) {
        uint256 price = getBuyPrice(amount);
        uint256 fee = (price * buyFeePercent) / feePrecision;
        return price + fee;
    }
    
    /// @notice Returns the sell price after deducting the 1% fee.
    function getSellPriceAfterFees(uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(amount);
        uint256 fee = (price * sellFeePercent) / feePrecision;
        return price - fee;
    }
    
    /**
     * @notice Constructor is payable to allow the deployer to provide initial ETH liquidity.
     * The provided ETH is treated as an initial buy.
     *
     * @param _creatorToken The ERC20 token address (should be pre-funded with tokens to be sold).
     * @param _protocolFeeAddress The address to which protocol fees will be sent.
     */
    constructor(address _creatorToken, address _protocolFeeAddress) payable {
        require(_creatorToken != address(0), "Invalid token address");
        require(_protocolFeeAddress != address(0), "Invalid fee address");
        creatorToken = _creatorToken;
        protocolFeeAddress = _protocolFeeAddress;
        
        // If deployer sends ETH during deployment, treat it as an initial buy.
        if (msg.value > 0) {
            _initialBuy(msg.sender, msg.value);
        }
    }
    
    /**
     * @notice Internal function that approximates the maximum number of tokens that can be
     * purchased with a given ETH amount (accounting for the 0.5% fee) using a binary search.
     * @param buyer The address of the buyer.
     * @param ethAmount The amount of ETH provided.
     */
    function _initialBuy(address buyer, uint256 ethAmount) internal {
        uint256 low = 0;
        // Here high is an approximate upper bound for the number of whole tokens to buy.
        uint256 high = (ethAmount / 1e9) * 2;
        uint256 mid;
        // Binary search with fixed iterations.
        for (uint256 i = 0; i < 20; i++) {
            mid = (low + high) / 2;
            // mid is a normalized token amount; convert it back to raw tokens.
            uint256 price = getBuyPriceAfterFees(mid * TOKEN_UNIT);
            if (price <= ethAmount) {
                low = mid;
            } else {
                high = mid;
            }
        }
        uint256 tokensToBuy = low * TOKEN_UNIT;
        require(tokensToBuy > 0, "Insufficient ETH for any tokens");
        
        uint256 totalPrice = getBuyPriceAfterFees(tokensToBuy);
        uint256 fee = (getBuyPrice(tokensToBuy) * buyFeePercent) / feePrecision;
        lifetimeProtocolFees += fee;
        
        require(ERC20(creatorToken).transfer(buyer, tokensToBuy), "Token transfer failed");
        
        // Refund any excess ETH.
        uint256 refund = ethAmount - totalPrice;
        if (refund > 0) {
            payable(buyer).transfer(refund);
        }
    }
    
    /**
     * @notice Buys tokens from the bonding curve.
     * @param amount The amount of tokens (in wei, representing whole tokens) the buyer wishes to purchase.
     */
    function buy(uint256 amount) external payable {
        uint256 grossPrice = getBuyPriceAfterFees(amount);
        require(msg.value >= grossPrice, "Insufficient ETH sent");
        
        uint256 fee = (getBuyPrice(amount) * buyFeePercent) / feePrecision;
        lifetimeProtocolFees += fee;
        
        require(ERC20(creatorToken).transfer(msg.sender, amount), "Token transfer failed");
        
        if (msg.value > grossPrice) {
            payable(msg.sender).transfer(msg.value - grossPrice);
        }
    }
    
    /**
     * @notice Sells tokens back to the bonding curve.
     * @param amount The amount of tokens (in wei, representing whole tokens) the seller wants to sell.
     */
    function sell(uint256 amount) external {
        ERC20 token = ERC20(creatorToken);
        require(token.balanceOf(msg.sender) >= amount, "Insufficient token balance");
        require(token.transferFrom(msg.sender, address(this), amount), "Token transferFrom failed");
        
        uint256 rawSellPrice = getSellPrice(amount);
        uint256 fee = (rawSellPrice * sellFeePercent) / feePrecision;
        uint256 netSellPrice = rawSellPrice - fee;
        lifetimeProtocolFees += fee;
        
        require(address(this).balance >= netSellPrice, "Insufficient ETH liquidity");
        payable(msg.sender).transfer(netSellPrice);
    }
    
    /**
     * @notice Provides additional liquidity by depositing CreatorToken into the contract.
     * @param amount The amount of CreatorToken to deposit.
     */
    function provideLiquidity(uint256 amount) external {
        require(ERC20(creatorToken).transferFrom(msg.sender, address(this), amount), "Token transferFrom failed");
    }
    
    /**
     * @notice Allows the protocol fee address to withdraw accumulated ETH fees.
     */
    function withdrawFees() external {
        require(msg.sender == protocolFeeAddress, "Only protocol fee address can withdraw");
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        payable(protocolFeeAddress).transfer(balance);
    }
    
    // Allow the contract to receive ETH (e.g., for sell orders or additional liquidity).
    receive() external payable {}
}
