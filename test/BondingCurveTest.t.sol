// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/BondingCurve.sol";
import "../src/CreatorToken.sol";

contract BondingCurveTest is Test {
    BondingCurve public bondingCurve;
    CreatorToken public token;
    address public protocolFeeAddress;
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;

    function setUp() public {
        protocolFeeAddress = 0xE2B48E911562a221619533a5463975Fdd92E7fC7;

        CreatorToken.TokenConfig memory config = CreatorToken.TokenConfig({
            totalSupply: INITIAL_SUPPLY,
            selfPercent: 10,
            marketPercent: 80,
            supporterPercent: 10,
            handle: keccak256(abi.encodePacked("test")),
            aiAgent: address(this)
        });

        // Create proper distributor config
        CreatorTokenSupporter.DistributorConfig memory distributorConfig = CreatorTokenSupporter.DistributorConfig({
            dailyDripAmount: 1000 * 1e18,
            dripInterval: 1 days,
            totalDays: 100
        });

        // Create proper vault config
        SelfTokenVault.VaultConfig memory vaultConfig = SelfTokenVault.VaultConfig({
            dripPercentage: 10,
            dripInterval: 30 days,
            lockTime: 180 days,
            lockedPercentage: 80
        });

        token = new CreatorToken(
            "Test Token",
            "TEST",
            abi.encode(config),
            abi.encode(distributorConfig),
            abi.encode(vaultConfig),
            address(this),
            address(0)
        );

        bondingCurve = BondingCurve(payable(token.getBondingCurveAddress()));
    }

    function testInitialSetup() public view {
        assertEq(address(bondingCurve.creatorToken()), address(token));
        assertEq(bondingCurve.protocolFeeAddress(), protocolFeeAddress);
        assertEq(bondingCurve.buyFeePercent(), 50); // 0.5%
        assertEq(bondingCurve.sellFeePercent(), 100); // 1%
    }

    function testGetPrice() public view {
        uint256 supply = 1000 * 1e18;
        uint256 amount = 100 * 1e18;

        uint256 price = bondingCurve.getPrice(supply, amount);
        uint256 expectedBasePrice = amount * bondingCurve.BASE_PRICE();
        uint256 expectedSlopeCost = bondingCurve.SLOPE() * (supply * amount + (amount * (amount - 1)) / 2);

        assertEq(price, expectedBasePrice + expectedSlopeCost);
    }

    function testBuyPricing() public view {
        uint256 amount = 100 * 1e18;

        uint256 rawPrice = bondingCurve.getBuyPrice(amount);
        uint256 priceWithFees = bondingCurve.getBuyPriceAfterFees(amount);

        // Check fee calculation
        uint256 expectedFee = (rawPrice * bondingCurve.buyFeePercent()) / bondingCurve.feePrecision();
        assertEq(priceWithFees, rawPrice + expectedFee);
    }

    function testSellPricing() public {
        // First buy some tokens to have supply
        uint256 buyAmount = 1000 * 1e18;
        uint256 buyPrice = bondingCurve.getBuyPriceAfterFees(buyAmount);

        hoax(address(this), buyPrice);
        bondingCurve.buy{value: buyPrice}(buyAmount);

        // Now test sell pricing
        uint256 sellAmount = 100 * 1e18;
        uint256 rawSellPrice = bondingCurve.getSellPrice(sellAmount);
        uint256 priceWithFees = bondingCurve.getSellPriceAfterFees(sellAmount);

        // Check fee calculation
        uint256 expectedFee = (rawSellPrice * bondingCurve.sellFeePercent()) / bondingCurve.feePrecision();
        assertEq(priceWithFees, rawSellPrice - expectedFee);
    }

    function testBuyAndSell() public {
        uint256 buyAmount = 100 * 1e18;
        uint256 buyPrice = bondingCurve.getBuyPriceAfterFees(buyAmount);

        // Buy tokens
        hoax(address(this), buyPrice);
        bondingCurve.buy{value: buyPrice}(buyAmount);

        assertEq(token.balanceOf(address(this)), buyAmount);

        // Approve tokens for selling
        token.approve(address(bondingCurve), buyAmount);

        // Sell tokens
        uint256 beforeBalance = address(this).balance;
        bondingCurve.sell(buyAmount);
        uint256 afterBalance = address(this).balance;

        assertTrue(afterBalance > beforeBalance);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testProvideLiquidity() public {
        uint256 amount = 1000 * 1e18;

         // Get initial balance of bonding curve
         uint256 initialBalance = token.balanceOf(address(bondingCurve));

        deal(address(token), address(this), amount);

        token.approve(address(bondingCurve), amount);
        bondingCurve.provideLiquidity(amount);

        assertEq(token.balanceOf(address(bondingCurve)), initialBalance + amount);
    }

    function testWithdrawFees() public {
        // Buy tokens to generate fees
        uint256 buyAmount = 1000 * 1e18;
        uint256 buyPrice = bondingCurve.getBuyPriceAfterFees(buyAmount);

        hoax(address(this), buyPrice);
        bondingCurve.buy{value: buyPrice}(buyAmount);

        // Check collected fees
        assertTrue(bondingCurve.lifetimeProtocolFees() > 0);

        // Properly impersonate the protocol fee address
        uint256 beforeBalance = protocolFeeAddress.balance;
        hoax(protocolFeeAddress); // Use hoax instead of vm.prank to ensure the address has ETH to pay for gas
        bondingCurve.withdrawFees();
        uint256 afterBalance = protocolFeeAddress.balance;

        assertTrue(afterBalance > beforeBalance);
    }

    function testFailInsufficientEthForBuy() public {
        uint256 buyAmount = 100 * 1e18;
        uint256 buyPrice = bondingCurve.getBuyPriceAfterFees(buyAmount);

        // Try to buy with insufficient ETH
        hoax(address(this), buyPrice - 1);
        bondingCurve.buy{value: buyPrice - 1}(buyAmount);
    }

    function testFailInsufficientTokensForSell() public {
        // Try to sell without having tokens
        bondingCurve.sell(100 * 1e18);
    }

    receive() external payable {}
}
