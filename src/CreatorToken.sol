// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./SelfTokenVault.sol";
import "./BondingCurve.sol";
import "./CreatorTokenSupporter.sol";

/*
─────────────────────────────────────────────
 2) CREATOR TOKEN (ERC20)
    Deploys SelfTokenVault, BondingCurve,
    and CreatorTokenSupporter
─────────────────────────────────────────────
*/

contract CreatorToken is ERC20 {
    // Addresses of the deployed sub-contracts.
    address public selfTokenVault;       // x% goes here
    address public bondingCurve;         // y% goes here
    address public supporterContract;    // z% goes here

    // The creator is the one who called from EntryPoint.
    address public creator;

    // The hash of creator handle.
    bytes32 public handle;
    
    // The AI agent address.
    address public aiAgent;

    // Total ERC20 supply.
    uint256 public totalERC20Supply;

    /**
     * @param _name Token name (used by ERC20).
     * @param _symbol Token symbol (used by ERC20).
     * @param _totalSupply Total ERC20 supply.
     * @param _selfPercent Percentage allocated to the SelfTokenVault (x).
     * @param _marketPercent Percentage allocated to the BondingCurve (y).
     * @param _supporterPercent Percentage allocated to the CreatorTokenSupporter (z).
     * @param _creator The address that will own this CreatorToken and its vault.
     * @param _aiAgent The address designated as the AI agent (owner of the supporter).
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint8 _selfPercent,
        uint8 _marketPercent,
        uint8 _supporterPercent,
        address _creator,
        bytes32 _handle,
        address _aiAgent
    ) ERC20(_name, _symbol) {
        require(
            _selfPercent + _marketPercent + _supporterPercent == 100,
            "Invalid percentage split"
        );

        creator = _creator;
        aiAgent = _aiAgent;
        handle = _handle;
        totalERC20Supply = _totalSupply;

        // Deploy the SelfTokenVault (x%).
        SelfTokenVault vault = new SelfTokenVault(address(this), _creator);
        selfTokenVault = address(vault);

        // Deploy the BondingCurve (y%).
        BondingCurve curve = new BondingCurve(address(this));
        bondingCurve = address(curve);

        // Deploy the CreatorTokenSupporter (z%), owned by the AI agent.
        CreatorTokenSupporter supporter = new CreatorTokenSupporter(address(this), _aiAgent);
        supporterContract = address(supporter);

        // Mint the ERC20 supply in three slices.
        uint256 selfTokens = (_totalSupply * _selfPercent) / 100;
        uint256 marketTokens = (_totalSupply * _marketPercent) / 100;
        uint256 supporterTokens = (_totalSupply * _supporterPercent) / 100;

        _mint(selfTokenVault, selfTokens);         // x% → SelfTokenVault
        _mint(bondingCurve, marketTokens);          // y% → BondingCurve
        _mint(supporterContract, supporterTokens);  // z% → CreatorTokenSupporter
    }

    // Optional: override ERC20 decimals.
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
