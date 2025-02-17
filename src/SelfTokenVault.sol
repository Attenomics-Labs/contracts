// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin contracts (make sure these are available in your project)
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title SelfTokenVault
/// @notice Holds self tokens so that the creator can later withdraw them.
contract SelfTokenVault is Ownable {
    IERC20 public token;

    constructor(IERC20 _token) Ownable(msg.sender){
        token = _token;
    }

    /// @notice Withdraw all tokens held by the vault.
    function withdraw() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        token.transfer(owner(), balance);
    }
}