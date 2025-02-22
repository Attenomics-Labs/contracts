// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

// Import all contracts
import {AttenomicsCreatorEntryPoint} from "../src/AttenomicsCreatorEntryPoint.sol";
import {CreatorToken} from "../src/CreatorToken.sol";
import {SelfTokenVault} from "../src/SelfTokenVault.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {GasliteDrop} from "../src/GasliteDrop.sol";
import {CreatorTokenSupporter} from "../src/CreatorTokenSupporter.sol";

contract Deploy is Script {
    // Store deployed addresses
    address public entryPoint;
    address public creatorToken;
    address public selfTokenVault;
    address public bondingCurve;
    address public gasliteDrop;
    address public supporter;
    address public protocolFeeAddress;
    address public aiAgent;

    function run() external {
        // Get private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions with higher gas price to replace pending tx
        vm.startBroadcast(deployerPrivateKey);

        // Add this line to ensure proper nonce
        uint64 nonce = vm.getNonce(vm.addr(deployerPrivateKey));
        vm.setNonce(vm.addr(deployerPrivateKey), nonce);

        // Set protocol addresses
        protocolFeeAddress = vm.addr(deployerPrivateKey);
        aiAgent = vm.addr(deployerPrivateKey);

        // 1. Deploy GasliteDrop
        GasliteDrop gasliteDropContract = new GasliteDrop();
        gasliteDrop = address(gasliteDropContract);
        console2.log("GasliteDrop:", gasliteDrop);

        // 2. Deploy EntryPoint
        AttenomicsCreatorEntryPoint entryPointContract = new AttenomicsCreatorEntryPoint(gasliteDrop);
        entryPoint = address(entryPointContract);
        console2.log("EntryPoint:", entryPoint);

        // 3. Authorize the AI agent
        entryPointContract.setAIAgent(aiAgent, true);
        console2.log("AI Agent authorized:", aiAgent);

        // 4. Deploy a sample Creator Token through EntryPoint
        // Prepare creator token config data
        bytes32 handle = entryPointContract.getHandleHash("sample_creator");
        bytes memory configData = abi.encode(
            CreatorToken.TokenConfig({
                totalSupply: 1_000_000 * 1e18, // 1M tokens
                selfPercent: 10,
                marketPercent: 80,
                supporterPercent: 10,
                handle: handle,
                aiAgent: aiAgent
            })
        );

        // Prepare distributor config data
        bytes memory distributorConfigData = abi.encode(
            CreatorTokenSupporter.DistributorConfig({
                dailyDripAmount: 1000 * 1e18, // 1000 tokens per day
                dripInterval: 1 days,
                totalDays: 100
            })
        );

        // Prepare vault config data
        bytes memory vaultConfigData = abi.encode(
            SelfTokenVault.VaultConfig({
                dripPercentage: 10, // 10% per interval
                dripInterval: 30 days,
                lockTime: 180 days,
                lockedPercentage: 80 // 80% locked, 20% immediate
            })
        );

        // Deploy creator token with all configs
        entryPointContract.deployCreatorToken(
            configData,
            distributorConfigData,
            vaultConfigData,
            "Sample Creator Token",
            "SCT",
            "ipfs://sample-metadata-uri"
        );
        
        // Add a small delay to ensure state is finalized
        vm.warp(block.timestamp + 1);
        
        // Get the deployed addresses from the entry point
        creatorToken = entryPointContract.creatorTokenByHandle(handle);
        CreatorToken token = CreatorToken(creatorToken);
        

        
        selfTokenVault = token.selfTokenVault();
        supporter = token.supporterContract();
        bondingCurve = token.bondingCurve(); // Get the existing bonding curve
        
        console2.log("CreatorToken:", creatorToken);
        console2.log("BondingCurve:", bondingCurve);

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\nDeployment Summary:");
        console2.log("==================");
        console2.log("GasliteDrop:", gasliteDrop);
        console2.log("EntryPoint:", entryPoint);
        console2.log("CreatorToken:", creatorToken);
        console2.log("BondingCurve:", bondingCurve);
        console2.log("Protocol Fee Address:", protocolFeeAddress);
        console2.log("AI Agent:", aiAgent);
    }
}