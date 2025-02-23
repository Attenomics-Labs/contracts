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
    // Pack the token configuration parameters in a struct.
    struct TokenConfig {
        uint256 totalSupply;
        uint8 selfPercent;
        uint8 marketPercent;
        uint8 supporterPercent;
        bytes32 handle;
        address aiAgent;
    }

    // Addresses of the deployed sub-contracts.
    address public selfTokenVault; // x% goes here
    address public bondingCurve; // y% goes here
    address public supporterContract; // z% goes here

    address public protocolFeeAddress = 0xE2B48E911562a221619533a5463975Fdd92E7fC7;

    // The creator (set by the EntryPoint).
    address public creator;

    // The hash of the creator's handle.
    bytes32 public handle;

    // The AI agent address.
    address public aiAgent;

    // Total ERC20 supply.
    uint256 public totalERC20Supply;

    /**
     * @param _name Token name (used by ERC20).
     * @param _symbol Token symbol (used by ERC20).
     * @param configData Packed configuration parameters as bytes.
     * @param distributorConfigData Packed configuration for the distributor contract.
     * @param vaultConfigData Packed configuration for the vault contract.
     * @param _creator The address that will own this CreatorToken and its vault.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        bytes memory configData,
        bytes memory distributorConfigData,
        bytes memory vaultConfigData,
        address _creator,
        address gasLiteDropContractAddress
    )
        ERC20(_name, _symbol)
    {
        // Decode the passed bytes into the TokenConfig struct.
        TokenConfig memory config = abi.decode(configData, (TokenConfig));
        require(config.selfPercent + config.marketPercent + config.supporterPercent == 100, "Invalid percentage split");

        creator = _creator;
        aiAgent = config.aiAgent;
        handle = config.handle;
        totalERC20Supply = config.totalSupply;

        // Mint tokens
        uint256 selfTokens = (config.totalSupply * config.selfPercent) / 100;
        uint256 marketTokens = (config.totalSupply * config.marketPercent) / 100;
        uint256 supporterTokens = (config.totalSupply * config.supporterPercent) / 100;

        // Deploy the SelfTokenVault (x%).
        SelfTokenVault vault = new SelfTokenVault(address(this), _creator, vaultConfigData, selfTokens);
        selfTokenVault = address(vault);

        // Deploy the BondingCurve (y%).
        BondingCurve curve = new BondingCurve(address(this), protocolFeeAddress);
        bondingCurve = address(curve);

        // Deploy the CreatorTokenSupporter (z%), owned by the AI agent.
        CreatorTokenSupporter supporter =
            new CreatorTokenSupporter(address(this), config.aiAgent, distributorConfigData, gasLiteDropContractAddress);
        supporterContract = address(supporter);

        _mint(selfTokenVault, selfTokens);
        _mint(bondingCurve, marketTokens);
        _mint(supporterContract, supporterTokens);
    }

    // Optional: override ERC20 decimals.
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    // Add these getter functions
    function getVaultAddress() public view returns (address) {
        return address(selfTokenVault);
    }

    function getSupporterAddress() public view returns (address) {
        return address(supporterContract);
    }

    //  this function is for the bonding curve
    function getBondingCurveAddress() public view returns (address) {
        return bondingCurve;
    }
}
