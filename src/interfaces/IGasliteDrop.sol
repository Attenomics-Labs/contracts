pragma solidity ^0.8.20;

interface IGasliteDrop {
    /**
     * @notice Airdrop ERC721 tokens to a list of addresses
     * @param _nft The address of the ERC721 contract
     * @param _addresses The addresses to airdrop to
     * @param _tokenIds The tokenIds to airdrop
     */
    function airdropERC721(
        address _nft,
        address[] calldata _addresses,
        uint256[] calldata _tokenIds
    ) external payable;

    /**
     * @notice Airdrop ERC20 tokens to a list of addresses
     * @param _token The address of the ERC20 contract
     * @param _addresses The addresses to airdrop to
     * @param _amounts The amounts to airdrop
     * @param _totalAmount The total amount to airdrop
     */
    function airdropERC20(
        address _token,
        address[] calldata _addresses,
        uint256[] calldata _amounts,
        uint256 _totalAmount
    ) external payable;

    /**
     * @notice Airdrop ETH to a list of addresses
     * @param _addresses The addresses to airdrop to
     * @param _amounts The amounts to airdrop
     */
    function airdropETH(
        address[] calldata _addresses,
        uint256[] calldata _amounts
    ) external payable;
}