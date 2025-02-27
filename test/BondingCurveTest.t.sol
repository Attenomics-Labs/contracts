// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/BondingCurve.sol";
import "./TestToken.sol";

contract BondingCurveTest is Test {
    BondingCurve public bondingCurve;
    TestToken public token;

    // We'll designate a protocol fee address.
    address public protocolFeeAddress =
        address(0x1234567890123456789012345678901234567890);

    // Mint 10,000,000 tokens of 18 decimals (for testing liquidity)
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18; // 1000 billion

    function setUp() public {
        // Deploy the test token and the bonding curve
        token = new TestToken(INITIAL_SUPPLY);
        bondingCurve = new BondingCurve(address(token), protocolFeeAddress);

        // Transfer some tokens to the curve as initial liquidity (e.g., 80,000,000 tokens).
        // (Adjust these numbers if needed to ensure sufficient liquidity.)
        token.transfer(address(bondingCurve), 80_000_000 * 1e18);
    }

    function testInitialSetup() public {
        assertEq(bondingCurve.creatorToken(), address(token));
        assertEq(bondingCurve.protocolFeeAddress(), protocolFeeAddress);
        assertEq(bondingCurve.buyFeePercent(), 50); // 0.5%
        assertEq(bondingCurve.sellFeePercent(), 100); // 1%
    }

    function testGetPrice() public {
        // Test the linear formula for a hypothetical supply = 1000 tokens, amount = 100 tokens.
        uint256 supply = 1000 * 1e18;
        uint256 amount = 100 * 1e18;

        // Replicate the formula:
        // 1) normS = supply / NORMALIZER, normA = amount / NORMALIZER.
        // 2) costUnits = normA * BASE_PRICE + SLOPE * (normS * normA + (normA * (normA - 1)) / 2).
        // 3) final cost = costUnits * (1 ether / SCALING_FACTOR).
        uint256 normS = supply / bondingCurve.NORMALIZER();
        uint256 normA = amount / bondingCurve.NORMALIZER();
        uint256 costUnits = normA *
            bondingCurve.BASE_PRICE() +
            bondingCurve.SLOPE() *
            (normS * normA + (normA * (normA - 1)) / 2);
        uint256 expected = (costUnits * 1 ether) /
            bondingCurve.SCALING_FACTOR();
        uint256 actual = bondingCurve.getPrice(supply, amount);

        assertEq(actual, expected);
    }

    function testBuyPricing() public {
        // Check that getBuyPriceAfterFees = getBuyPrice(...) + 0.5% fee.
        uint256 amount = 100 * 1e18;
        uint256 rawPrice = bondingCurve.getBuyPrice(amount);
        uint256 expectedFee = (rawPrice * bondingCurve.buyFeePercent()) /
            bondingCurve.feePrecision();
        uint256 actualBuyPrice = bondingCurve.getBuyPriceAfterFees(amount);
        assertEq(actualBuyPrice, rawPrice + expectedFee);
    }

    function testSellPricing() public {
        // First, buy tokens so that the effective supply is nonzero.
        uint256 buyAmount = 1000 * 1e18;
        uint256 cost = bondingCurve.getBuyPriceAfterFees(buyAmount);
        vm.deal(address(this), cost);
        bondingCurve.buy{value: cost}(buyAmount);

        // Now check the sell pricing.
        uint256 sellAmount = 100 * 1e18;
        uint256 rawPrice = bondingCurve.getSellPrice(sellAmount);
        uint256 fee = (rawPrice * bondingCurve.sellFeePercent()) /
            bondingCurve.feePrecision();
        uint256 afterFee = rawPrice - fee;

        assertEq(bondingCurve.getSellPriceAfterFees(sellAmount), afterFee);
    }

    function testGetBuyPriceAfterFees() public {
        uint256 buyAmount = 100 * 1e18;
        uint256 buyCost = bondingCurve.getBuyPriceAfterFees(buyAmount);
        console.log("Buy cost:", buyCost);
    }

    function testGetBuyPriceFromEth() external {
        uint256 ethToBuy = 1 ether;

        // Get the estimated number of tokens that can be bought with 1 ETH
        uint256 buyAmount = bondingCurve.getTokensForEth(ethToBuy);
        console.log("Buy amount:", buyAmount);

        // Ensure we got a valid amount of tokens
        require(buyAmount > 0, "Token amount should be greater than 0");

        // Get the actual ETH cost to buy this amount of tokens
        uint256 actualPrice = bondingCurve.getBuyPriceAfterFees(buyAmount);
        console.log("Expected ETH spent:", ethToBuy);
        console.log("Actual ETH spent:", actualPrice);

        // Verify that the ETH spent is approximately 1 ETH (allowing minor rounding differences)
        assertApproxEqAbs(actualPrice, ethToBuy, 1e16); // Allow ~0.01 ETH margin
    }

    function testBuyAndSell() public {
        uint256 buyAmount = 100 * 1e18;
        uint256 buyCost = bondingCurve.getBuyPriceAfterFees(buyAmount);

        // Provide ETH and buy tokens.
        vm.deal(address(this), buyCost);
        uint256 beforeBal = token.balanceOf(address(this));
        bondingCurve.buy{value: buyCost}(buyAmount);

        // Check that tokens were received.
        assertEq(token.balanceOf(address(this)) - beforeBal, buyAmount);

        // Approve and sell tokens.
        token.approve(address(bondingCurve), buyAmount);
        uint256 beforeEth = address(this).balance;
        bondingCurve.sell(buyAmount);
        uint256 afterEth = address(this).balance;

        // Expect an increase in ETH (though fees ensure a round-trip loss).
        assertTrue(afterEth > beforeEth);
    }

    function testBuyAndSellOneK() public {
        uint256 buyAmount = 1000 * 1e18;
        uint256 buyCost = bondingCurve.getBuyPriceAfterFees(buyAmount);

        vm.deal(address(this), buyCost);
        uint256 beforeBal = token.balanceOf(address(this));
        bondingCurve.buy{value: buyCost}(buyAmount);

        assertEq(token.balanceOf(address(this)) - beforeBal, buyAmount);

        token.approve(address(bondingCurve), buyAmount);
        uint256 beforeEth = address(this).balance;
        bondingCurve.sell(buyAmount);
        uint256 afterEth = address(this).balance;

        assertTrue(afterEth > beforeEth);
    }

    function testBuyAndSellOneMil() public {
        uint256 buyAmount = 1_000_000 * 1e18;
        uint256 buyCost = bondingCurve.getBuyPriceAfterFees(buyAmount);

        vm.deal(address(this), buyCost);
        uint256 beforeBal = token.balanceOf(address(this));
        bondingCurve.buy{value: buyCost}(buyAmount);

        assertEq(token.balanceOf(address(this)) - beforeBal, buyAmount);

        token.approve(address(bondingCurve), buyAmount);
        uint256 beforeEth = address(this).balance;
        bondingCurve.sell(buyAmount);
        uint256 afterEth = address(this).balance;

        assertTrue(afterEth > beforeEth);
    }

    function testProvideLiquidity() public {
        uint256 initialBal = token.balanceOf(address(bondingCurve));

        // Provide extra 1000 tokens.
        uint256 addAmount = 1000 * 1e18;
        token.transfer(address(this), addAmount);
        token.approve(address(bondingCurve), addAmount);
        bondingCurve.provideLiquidity(addAmount);

        uint256 finalBal = token.balanceOf(address(bondingCurve));
        assertEq(finalBal, initialBal + addAmount);
    }

    function testWithdrawFees() public {
        // Do a buy to generate fees.
        uint256 amt = 1000 * 1e18;
        uint256 price = bondingCurve.getBuyPriceAfterFees(amt);
        vm.deal(address(this), price);
        bondingCurve.buy{value: price}(amt);

        assertTrue(bondingCurve.lifetimeProtocolFees() > 0);

        uint256 preBal = protocolFeeAddress.balance;
        vm.deal(protocolFeeAddress, 10 ether); // Fund fee address for gas.
        vm.prank(protocolFeeAddress);
        bondingCurve.withdrawFees();
        uint256 postBal = protocolFeeAddress.balance;

        assertTrue(postBal > preBal);
    }

    // ======================
    //   Additional Test Cases
    // ======================

    /// @notice Test buying 10K tokens when the effective supply is still at 0.
    function testBuy10KTokens() public {
        uint256 buyAmount = 10_000 * 1e18;
        uint256 buyCost = bondingCurve.getBuyPriceAfterFees(buyAmount);
        vm.deal(address(this), buyCost);

        uint256 initialEffectiveSupply = bondingCurve.purchaseMarketSupply();
        uint256 initialCurveTokenBal = token.balanceOf(address(bondingCurve));

        bondingCurve.buy{value: buyCost}(buyAmount);

        uint256 finalEffectiveSupply = bondingCurve.purchaseMarketSupply();
        uint256 finalCurveTokenBal = token.balanceOf(address(bondingCurve));

        // Effective supply should increase by exactly buyAmount.
        assertEq(finalEffectiveSupply - initialEffectiveSupply, buyAmount);
        // The bonding curve's token balance should decrease by buyAmount.
        assertEq(initialCurveTokenBal - finalCurveTokenBal, buyAmount);
    }

    /// @notice Test the cost to buy 10K tokens after 1M tokens have been purchased.
    function testBuy10KAfter1MBuy() public {
        // First, buy 1M tokens.
        uint256 buyAmount1M = 1_000_000 * 1e18;
        uint256 cost1M = bondingCurve.getBuyPriceAfterFees(buyAmount1M);
        vm.deal(address(this), cost1M);
        bondingCurve.buy{value: cost1M}(buyAmount1M);
        uint256 effectiveSupplyAfter1M = bondingCurve.purchaseMarketSupply();
        assertEq(effectiveSupplyAfter1M, buyAmount1M);

        // Now, get cost to buy an additional 10K tokens.
        uint256 buyAmount10K = 10_000 * 1e18;
        uint256 cost10KAfter = bondingCurve.getBuyPriceAfterFees(buyAmount10K);

        // Calculate what 10K tokens would cost at an effective supply of 0.
        uint256 initialCostFor10K = bondingCurve.getPrice(0, buyAmount10K);
        uint256 initialCostFor10KAfterFees = initialCostFor10K +
            (initialCostFor10K * bondingCurve.buyFeePercent()) /
            bondingCurve.feePrecision();

        // The cost after 1M tokens should be higher than the initial cost.
        assertTrue(cost10KAfter > initialCostFor10KAfterFees);

        // Buy the additional 10K tokens.
        vm.deal(address(this), cost10KAfter);
        bondingCurve.buy{value: cost10KAfter}(buyAmount10K);

        uint256 newEffectiveSupply = bondingCurve.purchaseMarketSupply();
        assertEq(newEffectiveSupply, buyAmount1M + buyAmount10K);
    }

    /// @notice Simulate a profit scenario:
    /// Buyer A buys 10K tokens after 1M tokens have been purchased.
    /// Then Buyer B buys an extra 100K tokens to push the price higher.
    /// Buyer A then sells their 10K tokens. We log the difference.
    function testProfitScenario() public {
        // Step 1: Set up the curve with 1M tokens bought.
        uint256 buyAmount1M = 1_000_000 * 1e18;
        uint256 cost1M = bondingCurve.getBuyPriceAfterFees(buyAmount1M);
        vm.deal(address(this), cost1M);
        bondingCurve.buy{value: cost1M}(buyAmount1M);

        // Step 2: Buyer A buys 10K tokens.
        address buyerA = address(0xABCD);
        uint256 buyAmount10K = 10_000 * 1e18;
        uint256 cost10K = bondingCurve.getBuyPriceAfterFees(buyAmount10K);
        vm.deal(buyerA, cost10K);
        vm.prank(buyerA);
        bondingCurve.buy{value: cost10K}(buyAmount10K);

        // Record effective supply after Buyer A's purchase.
        uint256 effectiveSupplyAfterA = bondingCurve.purchaseMarketSupply();

        // Step 3: Buyer B buys 100K tokens to push the curve.
        address buyerB = address(0xBEEF);
        uint256 buyAmount100K = 100_000 * 1e18;
        uint256 cost100K = bondingCurve.getBuyPriceAfterFees(buyAmount100K);
        vm.deal(buyerB, cost100K);
        vm.prank(buyerB);
        bondingCurve.buy{value: cost100K}(buyAmount100K);

        // Step 4: Buyer A sells their 10K tokens.
        vm.prank(buyerA);
        TestToken(token).approve(address(bondingCurve), buyAmount10K);
        uint256 sellPayout = bondingCurve.getSellPriceAfterFees(buyAmount10K);
        uint256 balanceBeforeSell = buyerA.balance;
        vm.prank(buyerA);
        bondingCurve.sell(buyAmount10K);
        uint256 balanceAfterSell = buyerA.balance;

        // Calculate profit (note: with fees, a round-trip may still be negative).
        int256 profit = int256(sellPayout) - int256(cost10K);
        console.log(
            "Buyer A profit (wei):",
            uint256(profit < 0 ? int256(0) : profit)
        );
    }

    /// @notice Run a random buy–sell sequence over several iterations.
    function testRandomBuySellSequence() public {
        uint256 iterations = 10;
        uint256 netBought = 0;
        for (uint256 i = 0; i < iterations; i++) {
            // Simulate a buy amount increasing with each iteration.
            uint256 buyAmount = (i + 1) * 1000 * 1e18;
            uint256 cost = bondingCurve.getBuyPriceAfterFees(buyAmount);
            vm.deal(address(this), cost);
            bondingCurve.buy{value: cost}(buyAmount);
            netBought += buyAmount;
            // Every even iteration, sell half of the tokens bought in this iteration.
            if (i % 2 == 0) {
                uint256 sellAmount = buyAmount / 2;
                token.approve(address(bondingCurve), sellAmount);
                bondingCurve.sell(sellAmount);
                netBought -= sellAmount;
            }
        }
        // The effective supply should equal net tokens bought.
        assertEq(bondingCurve.purchaseMarketSupply(), netBought);
    }

    /// @notice Test multiple consecutive buys.
    function testMultipleConsecutiveBuys() public {
        uint256 totalBuy = 0;
        for (uint256 i = 0; i < 100; i++) {
            uint256 buyAmount = 500_000 * 1e18;
            uint256 cost = bondingCurve.getBuyPriceAfterFees(buyAmount);
            vm.deal(address(this), cost);
            bondingCurve.buy{value: cost}(buyAmount);
            totalBuy += buyAmount;
            assertEq(bondingCurve.purchaseMarketSupply(), totalBuy);
        }
    }

    /// @notice Test multiple consecutive sells.
    function testMultipleConsecutiveSells() public {
        // Buy 20000 tokens.
        uint256 buyAmount = 20_000 * 1e18;
        uint256 cost = bondingCurve.getBuyPriceAfterFees(buyAmount);
        vm.deal(address(this), cost);
        bondingCurve.buy{value: cost}(buyAmount);
        assertEq(bondingCurve.purchaseMarketSupply(), buyAmount);

        // Sell in two parts (10000 tokens each).
        uint256 sellAmount = 10_000 * 1e18;
        token.approve(address(bondingCurve), sellAmount);
        bondingCurve.sell(sellAmount);
        assertEq(bondingCurve.purchaseMarketSupply(), buyAmount - sellAmount);

        token.approve(address(bondingCurve), sellAmount);
        bondingCurve.sell(sellAmount);
        assertEq(bondingCurve.purchaseMarketSupply(), 0);
    }

    // ======================
    //   Failure Tests
    // ======================
    function testFailInsufficientEthForBuy() public {
        uint256 amt = 100 * 1e18;
        uint256 cost = bondingCurve.getBuyPriceAfterFees(amt);
        vm.deal(address(this), cost - 1);
        bondingCurve.buy{value: cost - 1}(amt);
    }

    function testFailInsufficientTokensForSell() public {
        bondingCurve.sell(100 * 1e18);
    }

    receive() external payable {}
}
