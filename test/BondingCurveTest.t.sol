// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/BondingCurve.sol";
import "./TestToken.sol";
contract BondingCurveTest is Test {
    BondingCurve public bondingCurve;
    TestToken public token;
    // Example protocol fee address.
    address public protocolFeeAddress = address(0x1234567890123456789012345678901234567890);
    // Mint 1,000,000 tokens (with 18 decimals)
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;

    function setUp() public {
        token = new TestToken(INITIAL_SUPPLY);
        bondingCurve = new BondingCurve(address(token), protocolFeeAddress);
        // Transfer 800,000 tokens to the BondingCurve contract as liquidity.
        token.transfer(address(bondingCurve), 800_000 * 1e18);
    }

    function testInitialSetup() public {
        assertEq(bondingCurve.creatorToken(), address(token));
        assertEq(bondingCurve.protocolFeeAddress(), protocolFeeAddress);
        assertEq(bondingCurve.buyFeePercent(), 50);
        assertEq(bondingCurve.sellFeePercent(), 100);
    }

    function testGetPrice() public {
        // Use raw token amounts (with 18 decimals)
        uint256 supply = 1000 * 1e18;
        uint256 amount = 100 * 1e18;
        // Normalize the values.
        uint256 normSupply = supply / 1e18; // 1000
        uint256 normAmount = amount / 1e18;   // 100
        uint256 sum1 = normSupply == 0 ? 0 : ((normSupply - 1) * normSupply * (2 * (normSupply - 1) + 1)) / 6;
        uint256 sum2 = (normSupply + normAmount - 1) * (normSupply + normAmount) * (2 * (normSupply + normAmount - 1) + 1) / 6;
        uint256 summation = sum2 - sum1;
        uint256 expectedPrice = (summation * 1 ether) / 16000;
        uint256 price = bondingCurve.getPrice(supply, amount);
        assertEq(price, expectedPrice);
    }

    function testBuyPricing() public {
        uint256 amount = 100 * 1e18;
        uint256 rawPrice = bondingCurve.getBuyPrice(amount);
        uint256 priceWithFees = bondingCurve.getBuyPriceAfterFees(amount);
        uint256 fee = (rawPrice * bondingCurve.buyFeePercent()) / bondingCurve.feePrecision();
        assertEq(priceWithFees, rawPrice + fee);
    }

    function testSellPricing() public {
        // First simulate a buy to add liquidity and update the supply.
        uint256 buyAmount = 1000 * 1e18;
        uint256 buyPrice = bondingCurve.getBuyPriceAfterFees(buyAmount);
        vm.deal(address(this), buyPrice);
        bondingCurve.buy{value: buyPrice}(buyAmount);
        
        // Now test sell pricing.
        uint256 sellAmount = 100 * 1e18;
        uint256 rawSellPrice = bondingCurve.getSellPrice(sellAmount);
        uint256 sellPriceWithFees = bondingCurve.getSellPriceAfterFees(sellAmount);
        uint256 fee = (rawSellPrice * bondingCurve.sellFeePercent()) / bondingCurve.feePrecision();
        assertEq(sellPriceWithFees, rawSellPrice - fee);
    }

 function testBuyAndSell() public {
        // Record the caller's initial token balance.
        uint256 initialBalance = token.balanceOf(address(this));

        uint256 buyAmount = 100 * 1e18;
        uint256 buyPrice = bondingCurve.getBuyPriceAfterFees(buyAmount);
        vm.deal(address(this), buyPrice);
        bondingCurve.buy{value: buyPrice}(buyAmount);

        // After buying, caller's balance should have increased by buyAmount.
        uint256 balanceAfterBuy = token.balanceOf(address(this));
        assertEq(balanceAfterBuy, initialBalance + buyAmount);

        // Approve the bonding curve to spend the bought tokens.
        token.approve(address(bondingCurve), buyAmount);
        uint256 ethBeforeSell = address(this).balance;
        bondingCurve.sell(buyAmount);
        uint256 ethAfterSell = address(this).balance;
        assertTrue(ethAfterSell > ethBeforeSell);

        // After selling, caller's token balance should return to the original value.
        uint256 balanceAfterSell = token.balanceOf(address(this));
        assertEq(balanceAfterSell, initialBalance);
    }
    function testProvideLiquidity() public {
        uint256 amount = 1000 * 1e18;
        uint256 initialLiquidity = token.balanceOf(address(bondingCurve));
        // Transfer tokens to this contract and approve the bonding curve.
        token.transfer(address(this), amount);
        token.approve(address(bondingCurve), amount);
        bondingCurve.provideLiquidity(amount);
        uint256 finalLiquidity = token.balanceOf(address(bondingCurve));
        assertEq(finalLiquidity, initialLiquidity + amount);
    }

    function testWithdrawFees() public {
        // Simulate a buy to generate fees.
        uint256 buyAmount = 1000 * 1e18;
        uint256 buyPrice = bondingCurve.getBuyPriceAfterFees(buyAmount);
        vm.deal(address(this), buyPrice);
        bondingCurve.buy{value: buyPrice}(buyAmount);
        assertTrue(bondingCurve.lifetimeProtocolFees() > 0);
        
        uint256 initialFeeBalance = protocolFeeAddress.balance;
        vm.deal(protocolFeeAddress, 1 ether);
        vm.prank(protocolFeeAddress);
        bondingCurve.withdrawFees();
        uint256 finalFeeBalance = protocolFeeAddress.balance;
        assertTrue(finalFeeBalance > initialFeeBalance);
    }

    function testFailInsufficientEthForBuy() public {
        uint256 buyAmount = 100 * 1e18;
        uint256 buyPrice = bondingCurve.getBuyPriceAfterFees(buyAmount);
        vm.deal(address(this), buyPrice - 1);
        bondingCurve.buy{value: buyPrice - 1}(buyAmount);
    }

    function testFailInsufficientTokensForSell() public {
        bondingCurve.sell(100 * 1e18);
    }
}
