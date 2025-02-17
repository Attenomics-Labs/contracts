// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin contracts (make sure these are available in your project)
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
/* 
  ─────────────────────────────────────────────
   2a) SELF TOKEN VAULT
       (Holds the creator’s x% tokens)
  ─────────────────────────────────────────────
*/

contract SelfTokenVault is Ownable {
    address public token;

    constructor(address _token, address _creator) Ownable(msg.sender){
        token = _token;
        // Transfer ownership of the vault to the creator
        _transferOwnership(_creator);
    }

    /**
     * @notice Withdraw all tokens from the vault to the vault owner (the creator).
     */
    function withdraw() external onlyOwner {
        uint256 balance = ERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens in vault");
        ERC20(token).transfer(owner(), balance);
    }
}