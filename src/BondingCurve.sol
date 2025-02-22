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
    
    // Parameters for a linear bonding curve.
    // BASE_PRICE: the starting price per token (when supply is zero).
    // SLOPE: the extra cost added per token for each token already issued.
    // (Values are in wei; 1e12 wei = 0.000001 ETH, 1e9 wei = 0.000000001 ETH)
    uint256 public constant BASE_PRICE = 1e12; // 0.000001 ETH per token
    uint256 public constant SLOPE = 1e9;       // 0.000000001 ETH per token per supply unit
    
    /**
     * @notice Computes the total cost for purchasing `amount` tokens starting at a given `supply`
     * using a linear bonding curve.
     *
     * Total cost = amount * BASE_PRICE + SLOPE * ( supply * amount + (amount*(amount-1))/2 )
     */
    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 linearCost = amount * BASE_PRICE;
        uint256 slopeCost = SLOPE * (supply * amount + (amount * (amount - 1)) / 2);
        return linearCost + slopeCost;
    }
    
    /// @notice Returns the raw buy price (without fees) for the given amount,
    /// based on the current token balance held by this contract.
    function getBuyPrice(uint256 amount) public view returns (uint256) {
        uint256 supply = ERC20(creatorToken).balanceOf(address(this));
        return getPrice(supply, amount);
    }
    
    /// @notice Returns the raw sell price (without fees) for the given amount.
    function getSellPrice(uint256 amount) public view returns (uint256) {
        uint256 supply = ERC20(creatorToken).balanceOf(address(this));
        require(supply >= amount, "Insufficient supply");
        return getPrice(supply - amount, amount);
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
        uint256 high = (ethAmount / 1e9) * 2; // approximate upper bound; adjust as needed
        uint256 mid;
        // Binary search with a fixed number of iterations.
        for (uint256 i = 0; i < 20; i++) {
            mid = (low + high) / 2;
            uint256 price = getBuyPriceAfterFees(mid);
            if (price <= ethAmount) {
                low = mid;
            } else {
                high = mid;
            }
        }
        uint256 tokensToBuy = low;
        require(tokensToBuy > 0, "Insufficient ETH for any tokens");
        
        uint256 totalPrice = getBuyPriceAfterFees(tokensToBuy);
        uint256 fee = (getBuyPrice(tokensToBuy) * buyFeePercent) / feePrecision;
        lifetimeProtocolFees += fee;
        
        // Transfer tokens from this contract to the buyer.
        ERC20(creatorToken).transfer(buyer, tokensToBuy);
        
        // Refund any excess ETH.
        uint256 refund = ethAmount - totalPrice;
        if (refund > 0) {
            payable(buyer).transfer(refund);
        }
    }
    
    /**
     * @notice Buys tokens from the bonding curve.
     * @param amount The amount of tokens the buyer wishes to purchase.
     */
    function buy(uint256 amount) external payable {
        uint256 grossPrice = getBuyPriceAfterFees(amount);
        require(msg.value >= grossPrice, "Insufficient ETH sent");
        
        uint256 fee = (getBuyPrice(amount) * buyFeePercent) / feePrecision;
        lifetimeProtocolFees += fee;
        
        ERC20(creatorToken).transfer(msg.sender, amount);
        
        if (msg.value > grossPrice) {
            payable(msg.sender).transfer(msg.value - grossPrice);
        }
    }
    
    /**
     * @notice Sells tokens back to the bonding curve.
     * @param amount The amount of tokens the seller wants to sell.
     */
    function sell(uint256 amount) external {
        ERC20 token = ERC20(creatorToken);
        require(token.balanceOf(msg.sender) >= amount, "Insufficient token balance");
        
        token.transferFrom(msg.sender, address(this), amount);
        
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
        ERC20(creatorToken).transferFrom(msg.sender, address(this), amount);
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
