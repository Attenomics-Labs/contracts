// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockBondingCurve
 * @notice A simplified mock implementation of the BondingCurve for testing
 */
contract MockBondingCurve {
    address public creatorToken;
    address public protocolFeeAddress;
    uint256 public purchaseMarketSupply;
    uint256 public lifetimeProtocolFees;

    // Fee configuration (basis points)
    uint256 public buyFeePercent = 50; // 0.5%
    uint256 public sellFeePercent = 100; // 1%
    uint256 public constant feePrecision = 10_000;

    // Simplified constructor that doesn't require token to be initialized
    constructor(address _creatorToken, address _protocolFeeAddress) payable {
        require(_creatorToken != address(0), "Invalid token address");
        require(_protocolFeeAddress != address(0), "Invalid fee address");
        creatorToken = _creatorToken;
        protocolFeeAddress = _protocolFeeAddress;
        purchaseMarketSupply = 0;
    }

    // Mock pricing functions
    function getPrice(uint256, uint256 amount) public pure returns (uint256) {
        return amount * 0.01 ether / 1e18;
    }

    function getBuyPrice(uint256 amount) public pure returns (uint256) {
        return amount * 0.01 ether / 1e18;
    }

    function getSellPrice(uint256 amount) public pure returns (uint256) {
        return amount * 0.009 ether / 1e18;
    }

    function getBuyPriceAfterFees(uint256 amount) public view returns (uint256) {
        uint256 rawPrice = getBuyPrice(amount);
        uint256 fee = (rawPrice * buyFeePercent) / feePrecision;
        return rawPrice + fee;
    }

    function getSellPriceAfterFees(uint256 amount) public view returns (uint256) {
        uint256 rawPrice = getSellPrice(amount);
        uint256 fee = (rawPrice * sellFeePercent) / feePrecision;
        return rawPrice - fee;
    }

    // Mock buy/sell functions
    function buy(uint256 amount) external payable returns (uint256) {
        uint256 cost = getBuyPriceAfterFees(amount);
        require(msg.value >= cost, "Insufficient ETH for buy");

        purchaseMarketSupply += amount;
        require(ERC20(creatorToken).transfer(msg.sender, amount), "Token transfer failed");

        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        return cost;
    }

    function sell(uint256 amount) external returns (uint256) {
        require(ERC20(creatorToken).transferFrom(msg.sender, address(this), amount), "Token transfer failed");

        uint256 payout = getSellPriceAfterFees(amount);
        purchaseMarketSupply -= amount;

        payable(msg.sender).transfer(payout);
        return payout;
    }

    // Allow the contract to receive ETH
    receive() external payable {}
    fallback() external payable {}
}
