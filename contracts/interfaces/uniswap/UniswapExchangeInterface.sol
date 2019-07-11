pragma solidity 0.5.10;

contract UniswapExchangeInterface {
    function getEthToTokenInputPrice(uint256 ethSold) external view returns (uint256 tokensBought);
    function getEthToTokenOutputPrice(uint256 tokensBought) external view returns (uint256 ethSold);
    function getTokenToEthInputPrice(uint256 tokensSold) external view returns (uint256 ethBought);
    function getTokenToEthOutputPrice(uint256 ethBought) external view returns (uint256 tokensSold);
    
    function tokenToEthTransferInput(
        uint256 tokensSold,
        uint256 minEth,
        uint256 deadline, 
        address recipient
    ) external returns (uint256  ethBought);
    function ethToTokenTransferInput(
        uint256 minTokens, 
        uint256 deadline, 
        address recipient
    ) external payable returns (uint256  tokensBought);
    function tokenToTokenTransferInput(
        uint256 tokensSold,
        uint256 minTokensBought,
        uint256 minEthBought,
        uint256 deadline,
        address recipient,
        address tokenAddr
    ) external returns (uint256 tokensBought);
}