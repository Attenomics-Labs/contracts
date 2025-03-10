// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SelfTokenVault.sol";

// Create a minimal mock token for testing
contract MockToken is Test {
    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;

    function mint(address account, uint256 amount) public {
        _balances[account] += amount;
        _totalSupply += amount;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }
}

contract SelfTokenVaultTest is Test {
    SelfTokenVault public vault;
    MockToken public token;
    address public creator;
    uint256 public constant INITIAL_BALANCE = 1_000_000 * 1e18;
    uint256 public constant LOCK_TIME = 180 days;
    uint256 public constant DRIP_INTERVAL = 30 days;

    function setUp() public {
        creator = address(0x123);
        token = new MockToken();

        // Create vault config
        SelfTokenVault.VaultConfig memory vaultConfig = SelfTokenVault.VaultConfig({
            dripPercentage: 10,
            dripInterval: DRIP_INTERVAL,
            lockTime: LOCK_TIME,
            lockedPercentage: 80
        });

        // Calculate self tokens amount (10% of total)
        uint256 selfTokens = INITIAL_BALANCE * 10 / 100;

        // Deploy the vault directly
        vault = new SelfTokenVault(address(token), creator, abi.encode(vaultConfig), selfTokens);

        // Mint tokens to the vault
        token.mint(address(vault), selfTokens);
    }

    function testInitialSetup() public view {
        // Calculate expected self tokens (10% of INITIAL_BALANCE)
        uint256 expectedSelfTokens = (INITIAL_BALANCE * 10) / 100;

        assertEq(vault.token(), address(token));
        assertEq(vault.owner(), creator);
        assertEq(vault.initialBalance(), expectedSelfTokens); // Fix this line

        assertTrue(vault.initialized());
    }

    function testMultipleIntervalsVesting() public {
        // Move time past lock period and multiple intervals
        vm.warp(block.timestamp + LOCK_TIME + (DRIP_INTERVAL * 3));

        // Calculate expected self tokens first
        uint256 selfTokens = (INITIAL_BALANCE * 10) / 100;

        // Calculate expected available amount
        // 20% immediate + (3 * 10%) of 80% after three intervals
        uint256 immediateAmount = (selfTokens * 20) / 100;
        uint256 lockedAmount = (selfTokens * 80) / 100;
        uint256 vestedAmount = (lockedAmount * 30) / 100; // 3 intervals * 10%

        assertEq(vault.availableForWithdrawal(), immediateAmount + vestedAmount);
    }

    function testFullVestingPeriod() public {
        // Move time way past all vesting periods
        vm.warp(block.timestamp + LOCK_TIME + (DRIP_INTERVAL * 20));

        // Calculate expected self tokens
        uint256 expectedSelfTokens = (INITIAL_BALANCE * 10) / 100;

        vm.prank(creator);
        vault.withdraw();

        // Should have received all self tokens
        assertEq(token.balanceOf(creator), expectedSelfTokens);
        assertEq(vault.withdrawn(), expectedSelfTokens);
    }

    function testImmediatelyAvailableTokens() public view {
        uint256 selfTokens = (INITIAL_BALANCE * 10) / 100; // Get self token amount
        // 20% should be immediately available (100 - 80% locked)
        uint256 expectedImmediate = (selfTokens * 20) / 100;
        assertEq(vault.availableForWithdrawal(), expectedImmediate);
    }

    function testVestingSchedule() public {
        vm.warp(block.timestamp + LOCK_TIME + DRIP_INTERVAL);

        uint256 selfTokens = (INITIAL_BALANCE * 10) / 100;
        uint256 immediateAmount = (selfTokens * 20) / 100;
        uint256 lockedAmount = (selfTokens * 80) / 100;
        uint256 firstDripAmount = (lockedAmount * 10) / 100;

        assertEq(vault.availableForWithdrawal(), immediateAmount + firstDripAmount);
    }

    function testWithdraw() public {
        vm.startPrank(creator);

        // Initial withdrawal (immediate amount)
        uint256 initialAvailable = vault.availableForWithdrawal();
        vault.withdraw();
        assertEq(token.balanceOf(creator), initialAvailable);
        assertEq(vault.withdrawn(), initialAvailable);

        // Move time forward and withdraw again
        vm.warp(block.timestamp + LOCK_TIME + DRIP_INTERVAL);
        uint256 newlyAvailable = vault.availableForWithdrawal();
        vault.withdraw();
        assertEq(token.balanceOf(creator), initialAvailable + newlyAvailable);
        assertEq(vault.withdrawn(), initialAvailable + newlyAvailable);

        vm.stopPrank();
    }

    function testFailWithdrawUnauthorized() public {
        vm.prank(address(0xdead));
        vault.withdraw();
    }

    function testFailWithdrawNoTokensAvailable() public {
        // Withdraw immediate amount
        vm.startPrank(creator);
        vault.withdraw();

        // Try to withdraw again immediately (should fail)
        vault.withdraw();
        vm.stopPrank();
    }
}