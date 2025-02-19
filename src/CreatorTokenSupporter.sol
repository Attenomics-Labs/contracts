// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title CreatorTokenSupporter
 * @notice Holds tokens (z%) that will be distributed over time.
 *         In addition to its constructor configuration (decoded from distributorConfigData),
 *         it supports off-chain signed distribution calls. A new distribution call is made
 *         by passing a packed bytes value encoding a DistributionData struct (with recipients,
 *         amounts, and totalAmount) along with a signature. The signature is verified using
 *         the standard ECDSA procedure in the _verifyDistributionData function before executing
 *         the distribution.
 */
contract CreatorTokenSupporter is Ownable {
    using ECDSA for bytes32;

    // Address of the CreatorToken (ERC20) managed by this contract.
    address public creatorToken;
    address public aiAgent;

    // Configuration used in the constructor.
    struct DistributorConfig {
        uint256 dailyDripAmount; // Amount of tokens to distribute per day.
        uint256 dripInterval;    // Interval (in seconds) between drips.
        uint256 totalDays;       // Total number of days for distribution.
    }
    DistributorConfig public distributorConfig;

    // New distribution data struct for actual distribution calls.
    struct DistributionData {
        address[] recipients;
        uint256[] amounts;
        uint256 totalAmount;
    }

    modifier onlyAiAgent() {
        require(msg.sender == aiAgent, "Only AI agent can call this function");
        _;
    }

    constructor(address _creatorToken, address _aiAgent, bytes memory distributorConfigData) Ownable(msg.sender) {
        creatorToken = _creatorToken;
        // Decode the distributor configuration data.
        DistributorConfig memory config = abi.decode(distributorConfigData, (DistributorConfig));
        distributorConfig = config;
        // Transfer ownership of the supporter contract to the AI agent.
        aiAgent = _aiAgent;
    }

    /**
     * @notice Verifies that the provided DistributionData is signed by the AI agent (owner).
     * @param data The DistributionData struct to verify.
     * @param signature The signature over the hash of the distribution data.
     * @return True if the signature is valid, false otherwise.
     */
    function _verifyDistributionData(DistributionData memory data, bytes memory signature) internal view returns (bool) {
        // Compute the hash of the distribution data.
        bytes32 dataHash = keccak256(abi.encode(data.recipients, data.amounts, data.totalAmount));
        // Apply the Ethereum Signed Message prefix.
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(dataHash);
        // Recover the signer from the signature.
        address signer = ethSignedHash.recover(signature);
        // Check that the recovered signer is the AI agent (i.e. the owner).
        return signer == aiAgent;
    }

    /**
     * @notice Internal function to perform distribution using the provided DistributionData.
     * @param data The DistributionData struct containing recipients, amounts, and totalAmount.
     */
    function _distribute(DistributionData memory data) internal {
        // Optionally verify that the sum of amounts equals the totalAmount.
        uint256 sum;
        for (uint256 i = 0; i < data.amounts.length; i++) {
            sum += data.amounts[i];
        }
        require(sum == data.totalAmount, "Total amount mismatch");

        // Distribute tokens to each recipient.
        for (uint256 i = 0; i < data.recipients.length; i++) {
            ERC20(creatorToken).transfer(data.recipients[i], data.amounts[i]);
        }
    }

    /**
     * @notice Distributes tokens based on off-chain signed distribution data.
     * @param distributionDataBytes Packed bytes encoding a DistributionData struct.
     * @param signature The signature over the distribution data, produced off-chain by the AI agent.
     */
    function distributeWithData(bytes memory distributionDataBytes, bytes memory signature) external {
        // Decode the distribution data.
        DistributionData memory data = abi.decode(distributionDataBytes, (DistributionData));
        // Verify the signature using the helper function.
        require(_verifyDistributionData(data, signature), "Invalid signature");
        _distribute(data);
    }

    /**
     * @notice Directly distributes tokens from this contract to multiple recipients.
     * @dev Only the AI agent (owner) can call this function.
     * @param recipients Array of addresses to receive tokens.
     * @param amounts Array of token amounts corresponding to each recipient.
     */
    function distribute(address[] calldata recipients, uint256[] calldata amounts) external onlyAiAgent {
        
    }
}
