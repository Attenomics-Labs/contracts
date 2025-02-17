// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin contracts (make sure these are available in your project)
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SelfTokenVault.sol";

/// @title CreatorToken
/// @notice ERC20 token that splits total supply into three parts:
/// - Self tokens are sent to a vault,
/// - Market tokens are sent to a specified market address,
/// - Reserved tokens are held by the contract for later distribution.
/// The constructor accepts an extra parameter, `creator`, to immediately set the owner.
contract CreatorToken is ERC20, Ownable {
    SelfTokenVault public selfTokenVault;
    address public marketAddress;
    uint256 public contractReserved;

    /// @param name Token name.
    /// @param symbol Token symbol.
    /// @param totalSupply Total token supply (in smallest unit).
    /// @param selfPercentage Percentage allocated to self tokens.
    /// @param marketPercentage Percentage allocated to market tokens.
    /// @param contractPercentage Percentage allocated to reserved tokens.
    /// @param marketAddr Address that receives market tokens.
    /// @param creator Address that will become the owner of this token and its vault.
    constructor(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint8 selfPercentage,
        uint8 marketPercentage,
        uint8 contractPercentage,
        address marketAddr,
        address creator
    ) ERC20(name, symbol) Ownable(msg.sender){
        require(
            selfPercentage + marketPercentage + contractPercentage == 100,
            "Percentages must add to 100"
        );

        // Calculate each portion based on the total supply.
        uint256 selfAmount = (totalSupply * selfPercentage) / 100;
        uint256 marketAmount = (totalSupply * marketPercentage) / 100;
        uint256 contractAmount = (totalSupply * contractPercentage) / 100;

        // Deploy the vault for self tokens and transfer its ownership to the creator.
        selfTokenVault = new SelfTokenVault(IERC20(address(this)));
        selfTokenVault.transferOwnership(creator);

        // Mint tokens for each category.
        _mint(address(selfTokenVault), selfAmount);
        marketAddress = marketAddr;
        _mint(marketAddress, marketAmount);
        contractReserved = contractAmount;
        _mint(address(this), contractAmount);

        // Transfer the token contract's ownership to the creator.
        _transferOwnership(creator);
    }

    /// @notice Distribute reserved tokens to a recipient.
    /// @param recipient Address to receive tokens.
    /// @param amount Amount to distribute.
    function distributeReserved(address recipient, uint256 amount) external onlyOwner {
        require(amount <= balanceOf(address(this)), "Not enough reserved tokens");
        _transfer(address(this), recipient, amount);
    }
}
