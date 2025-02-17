// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin contracts (make sure these are available in your project)
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/* 
  ─────────────────────────────────────────────
   2c) CREATOR TOKEN SUPPORTER (AI/Distributor)
       (Holds z% tokens)
  ─────────────────────────────────────────────
*/
contract CreatorTokenSupporter is Ownable {
    address public creatorToken;

    constructor(address _creatorToken, address aiAgent) Ownable(msg.sender){
        creatorToken = _creatorToken;
        // Transfer ownership of the supporter contract to the AI agent
        _transferOwnership(aiAgent);
    }

    /**
     * @notice Distribute tokens from this contract to multiple recipients.
     * @dev Only the AI agent (owner) can call this in this example.
     */
    function distribute(address[] calldata recipients, uint256[] calldata amounts) external onlyOwner {
        require(recipients.length == amounts.length, "Mismatched arrays");
        for (uint256 i = 0; i < recipients.length; i++) {
            ERC20(creatorToken).transfer(recipients[i], amounts[i]);
        }
    }
}
