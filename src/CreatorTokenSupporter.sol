// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IGasliteDrop} from "./interfaces/IGasliteDrop.sol";

/**
 * @dev security tradeoff suppose that everytime we do an airdrop we verify whether the token that has been distributed are correctly or not for particular peroiod of time x-y then the issue comes is that we have a tradeoff of gas cost but not having it is being reliable on ai agent that it actually does the airdrop correct
 */

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
    // AI agent address (set as the owner in the constructor).
    address public aiAgent;
    // Address of the GasliteDrop contract.
    address public gasLiteDropAddress;

    // Mapping to track used hashes to prevent double-spending.
    mapping(bytes32 => bool) public usedHashes;

    // Track the total tokens distributed so far.
    uint256 public totalDistributed;

    // Configuration used in the constructor.
    struct DistributorConfig {
        uint256 dailyDripAmount; // Amount of tokens to distribute per day.
        uint256 dripInterval; // Interval (in seconds) between drips.
        uint256 totalDays; // Total number of days for distribution.
    }

    DistributorConfig public distributorConfig;

    // New distribution data struct for actual distribution calls.
    struct DistributionData {
        address[] recipients;
        uint256[] amounts;
        uint256 totalAmount;
    }

    event DistributionExecuted(bytes32 indexed dataHash, address indexed executor);
    event AIAgentUpdated(address indexed agent, bool allowed);

    modifier onlyAiAgent() {
        require(msg.sender == aiAgent, "Only AI agent can call this function");
        _;
    }

    constructor(
        address _creatorToken,
        address _aiAgent,
        bytes memory distributorConfigData,
        address _gasLiteDropAddress
    )
        Ownable(msg.sender)
    {
        require(_creatorToken != address(0), "Invalid token address");
        require(_aiAgent != address(0), "Invalid AI agent address");
        require(_gasLiteDropAddress != address(0), "Invalid GasliteDrop address");
        
        creatorToken = _creatorToken;
        // Decode the distributor configuration data.
        DistributorConfig memory config = abi.decode(distributorConfigData, (DistributorConfig));
        distributorConfig = config;
        aiAgent = _aiAgent;
        gasLiteDropAddress = _gasLiteDropAddress;
        // Transfer ownership of the supporter contract to the AI agent.
        _transferOwnership(_aiAgent);
    }

    /**
     * @notice Verifies that the provided DistributionData is signed by the AI agent (owner)
     *         and that its hash has not been used before.
     * @param data The DistributionData struct to verify.
     * @param signature The signature over the hash of the distribution data.
     * @return True if the signature is valid, false otherwise.
     */
    function _verifyDistributionData(
        DistributionData memory data,
        bytes memory signature
    )
        internal
        view
        returns (bool)
    {
        // Compute the hash of the distribution data.
        bytes32 dataHash = keccak256(abi.encode(data.recipients, data.amounts, data.totalAmount));
        require(!usedHashes[dataHash], "Hash already used"); // Prevent double spending
        // Apply the Ethereum Signed Message prefix.
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(dataHash);
        // Recover the signer from the signature.
        address signer = ethSignedHash.recover(signature);
        // Check that the recovered signer is the AI agent.
        return signer == aiAgent;
    }

    /**
     * @notice Internal function to perform distribution using the provided DistributionData.
     * @param data The DistributionData struct containing recipients, amounts, and totalAmount.
     */
    function _distribute(DistributionData memory data) internal {
        // Call the external GasliteDrop contract to perform the airdrop.
        IGasliteDrop(gasLiteDropAddress).airdropERC20(creatorToken, data.recipients, data.amounts, data.totalAmount);
    }

    /**
     * @notice Distributes tokens based on off-chain signed distribution data.
     *         Before distribution, it checks that the contract's current token balance is sufficient,
     *         and it updates the totalDistributed counter.
     * @param distributionDataBytes Packed bytes encoding a DistributionData struct.
     * @param signature The signature over the distribution data, produced off-chain by the AI agent.
     */
    function distributeWithData(bytes memory distributionDataBytes, bytes memory signature) external {
        // Decode the distribution data.
        DistributionData memory data = abi.decode(distributionDataBytes, (DistributionData));
        // Compute the hash of the distribution data.
        bytes32 dataHash = keccak256(abi.encode(data.recipients, data.amounts, data.totalAmount));
        // Verify the signature using the helper function.
        require(_verifyDistributionData(data, signature), "Invalid signature");
        // Check that the contract has enough tokens for this distribution.
        uint256 currentBalance = ERC20(creatorToken).balanceOf(address(this));
        require(currentBalance >= data.totalAmount, "Insufficient contract balance");
        // Mark hash as used to prevent double-spending.
        usedHashes[dataHash] = true;
        // Execute distribution.
        _distribute(data);
        // Update total distributed tokens.
        totalDistributed += data.totalAmount;
        emit DistributionExecuted(dataHash, msg.sender);
    }

    /**
     * @notice Directly distributes tokens from this contract to multiple recipients.
     *         Only the AI agent (owner) can call this function.
     * @param recipients Array of addresses to receive tokens.
     * @param amounts Array of token amounts corresponding to each recipient.
     */
    function distribute(
        address[] calldata recipients,
        uint256[] calldata amounts,
        uint256 totalAmount
    )
        external
        onlyAiAgent
    {
        IGasliteDrop(gasLiteDropAddress).airdropERC20(creatorToken, recipients, amounts, totalAmount);
        totalDistributed += totalAmount;
        emit DistributionExecuted(keccak256(abi.encode(recipients, amounts, totalAmount)), msg.sender);
    }
}
