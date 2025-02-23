// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/BondingCurve.sol";
import "./TestToken.sol";

contract BondingCurveTest is Test {
    BondingCurve public bondingCurve;
    TestToken public token;

    // We'll designate a protocol fee address.
    address public protocolFeeAddress = address(0x1234567890123456789012345678901234567890);

    // Mint 1,000,000 tokens of 18 decimals
    uint256 public constant INITIAL_SUPPLY = 10000000000 * 1e18;

    function setUp() public {
        // Deploy the test token and the bonding curve
        token = new TestToken(INITIAL_SUPPLY);
        bondingCurve = new BondingCurve(address(token), protocolFeeAddress);

        // Transfer some tokens to the curve as initial liquidity (e.g., 800k tokens).
        token.transfer(address(bondingCurve), 80000000 * 1e18);
    }

    function testInitialSetup() public {
        assertEq(bondingCurve.creatorToken(), address(token));
        assertEq(bondingCurve.protocolFeeAddress(), protocolFeeAddress);
        assertEq(bondingCurve.buyFeePercent(), 50);    // 0.5%
        assertEq(bondingCurve.sellFeePercent(), 100);  // 1%
    }

    function testGetPrice() public {
        // We'll test the linear formula for a hypothetical supply = 1000 tokens, amount = 100 tokens
        // in raw wei terms, that's 1000e18, 100e18.
        uint256 supply = 1000 * 1e18;
        uint256 amount = 100 * 1e18;

        // We'll replicate the formula:
        //  1) normS = supply/1e9, normA = amount/1e9
        //  2) costUnits = normA*BASE_PRICE + SLOPE*(normS*normA + normA*(normA-1)/2)
        //  3) final = costUnits*(1 ether / SCALING_FACTOR)
        // We'll do this same calculation in the test and compare to getPrice(supply, amount).
        uint256 normS = supply / bondingCurve.NORMALIZER();
        uint256 normA = amount / bondingCurve.NORMALIZER();
        uint256 costUnits = normA * bondingCurve.BASE_PRICE()
            + bondingCurve.SLOPE() * (
                normS * normA + (normA * (normA - 1)) / 2
            );
        uint256 expected = (costUnits * 1 ether) / bondingCurve.SCALING_FACTOR();
        uint256 actual = bondingCurve.getPrice(supply, amount);

        assertEq(actual, expected);
    }

    function testBuyPricing() public {
        // Check that getBuyPriceAfterFees = getBuyPrice(...) + 0.5%
        uint256 amount = 100 * 1e18;
        uint256 rawPrice = bondingCurve.getBuyPrice(amount);
        uint256 expectedFee = (rawPrice * bondingCurve.buyFeePercent()) / bondingCurve.feePrecision();
        uint256 actualBuyPrice = bondingCurve.getBuyPriceAfterFees(amount);
        assertEq(actualBuyPrice, rawPrice + expectedFee);
    }

    function testSellPricing() public {
        // We'll buy tokens first so that the supply is effectively changed.
        uint256 buyAmount = 1000 * 1e18;
        uint256 cost = bondingCurve.getBuyPriceAfterFees(buyAmount);
        vm.deal(address(this), cost);
        bondingCurve.buy{value: cost}(buyAmount);

        // Now we check the rawSellPrice and priceAfterFees for some subset
        uint256 sellAmount = 100 * 1e18;
        uint256 rawPrice = bondingCurve.getSellPrice(sellAmount);
        uint256 fee = (rawPrice * bondingCurve.sellFeePercent()) / bondingCurve.feePrecision();
        uint256 afterFee = rawPrice - fee;

        assertEq(bondingCurve.getSellPriceAfterFees(sellAmount), afterFee);
    }

    function testBuyAndSell() public {
        uint256 buyAmount = 100 * 1e18;
        uint256 buyCost = bondingCurve.getBuyPriceAfterFees(buyAmount);

        // Provide the ETH and buy
        vm.deal(address(this), buyCost);
        uint256 beforeBal = token.balanceOf(address(this));
        bondingCurve.buy{value: buyCost}(buyAmount);

        // Check we received tokens
        assertEq(token.balanceOf(address(this)) - beforeBal, buyAmount);

        // Approve and sell
        token.approve(address(bondingCurve), buyAmount);
        uint256 beforeEth = address(this).balance;
        beforeBal = token.balanceOf(address(this));
        bondingCurve.sell(buyAmount);
        uint256 afterEth = address(this).balance;

        // We should have more ETH than before
        assertTrue(afterEth > beforeEth);


    }


    function testBuyAndSellOneK() public {
        uint256 buyAmount = 1000 * 1e18;
        uint256 buyCost = bondingCurve.getBuyPriceAfterFees(buyAmount);

        // Provide the ETH and buy
        vm.deal(address(this), buyCost);
        uint256 beforeBal = token.balanceOf(address(this));
        bondingCurve.buy{value: buyCost}(buyAmount);

        // Check we received tokens
        assertEq(token.balanceOf(address(this)) - beforeBal, buyAmount);

        // Approve and sell
        token.approve(address(bondingCurve), buyAmount);
        uint256 beforeEth = address(this).balance;
        beforeBal = token.balanceOf(address(this));
        bondingCurve.sell(buyAmount);
        uint256 afterEth = address(this).balance;

        // We should have more ETH than before
        assertTrue(afterEth > beforeEth);
    }

       function testBuyAndSellOneMil() public { 
        // 0.0502499999999598ether =  140.77$
        uint256 buyAmount = 1000000 * 1e18;
        uint256 buyCost = bondingCurve.getBuyPriceAfterFees(buyAmount);

        // Provide the ETH and buy
        vm.deal(address(this), buyCost);
        uint256 beforeBal = token.balanceOf(address(this));
        bondingCurve.buy{value: buyCost}(buyAmount);

        // Check we received tokens
        assertEq(token.balanceOf(address(this)) - beforeBal, buyAmount);

        // Approve and sell
        token.approve(address(bondingCurve), buyAmount);
        uint256 beforeEth = address(this).balance;
        beforeBal = token.balanceOf(address(this));
        bondingCurve.sell(buyAmount);
        uint256 afterEth = address(this).balance;

        // We should have more ETH than before
        assertTrue(afterEth > beforeEth);

        // 49499999999960400 
        // 0.0494999999999604 ether = 138.77$
    }   

    function testProvideLiquidity() public {
        uint256 initialBal = token.balanceOf(address(bondingCurve));

        // We'll provide extra 1000 tokens
        uint256 addAmount = 1000 * 1e18;
        token.transfer(address(this), addAmount);
        token.approve(address(bondingCurve), addAmount);
        bondingCurve.provideLiquidity(addAmount);

        uint256 finalBal = token.balanceOf(address(bondingCurve));
        assertEq(finalBal, initialBal + addAmount);
    }

    function testWithdrawFees() public {
        // We'll do a buy to generate fees
        uint256 amt = 1000 * 1e18;
        uint256 price = bondingCurve.getBuyPriceAfterFees(amt);
        vm.deal(address(this), price);
        bondingCurve.buy{value: price}(amt);

        // The curve has accumulated fees
        assertTrue(bondingCurve.lifetimeProtocolFees() > 0);

        // Withdraw fees from the protocol fee address
        uint256 preBal = protocolFeeAddress.balance;
        vm.deal(protocolFeeAddress, 10 ether); // just to fund gas
        vm.prank(protocolFeeAddress);
        bondingCurve.withdrawFees();
        uint256 postBal = protocolFeeAddress.balance;

        // We expect the protocol fee address to have gained some ETH
        assertTrue(postBal > preBal);
    }

    // ======================
    //   Failure Tests
    // ======================
    function testFailInsufficientEthForBuy() public {
        // If we pass 1 wei less than required, we revert
        uint256 amt = 100 * 1e18;
        uint256 cost = bondingCurve.getBuyPriceAfterFees(amt);
        vm.deal(address(this), cost - 1);
        bondingCurve.buy{value: cost - 1}(amt);
    }

    function testFailInsufficientTokensForSell() public {
        // Attempt to sell tokens we don't have
        bondingCurve.sell(100 * 1e18);
    }

    receive() external payable {}
}
