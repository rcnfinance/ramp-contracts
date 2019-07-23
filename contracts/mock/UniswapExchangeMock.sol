pragma solidity 0.5.10;

import 'openzeppelin-solidity/contracts/token/ERC20/IERC20.sol';

interface IUniswapExchange{
    function getEthToTokenOutputPrice(uint256 tokensBought) external view returns (uint256);
    function getTokenToEthOutputPrice(uint256 tokensBought) external view returns (uint256);

    function ethToTokenSwapOutput(uint256 minTokens, uint deadline) external payable returns (uint256);
    function tokenToTokenSwapOutput(uint256 tokensSold, uint256 minTokensBought, uint256 minEthBought, uint256 deadline, address tokenAddr) external returns (uint256  tokensBought);
}

contract UniswapExchangeMock is IUniswapExchange {
    IERC20 inputToken;
    IERC20 outputToken;

    constructor(address inputTokenAddress, address outputTokenAddress) public {
        inputToken = IERC20(inputTokenAddress);
        outputToken = IERC20(outputTokenAddress);
    }
    function getEthToTokenOutputPrice(uint256 tokensBought) external view returns (uint256) {
        return tokensBought;
    }

    function getTokenToEthOutputPrice(uint256 tokensBought) external view returns (uint256) {
        return tokensBought;
    }

    function ethToTokenSwapOutput(uint256 minTokens, uint deadline) public payable returns (uint256) {
        uint256 purchasedTokens = msg.value;
        require(outputToken.transfer(msg.sender, purchasedTokens), "couldnt buy token");
        return purchasedTokens;
    }
    function tokenToTokenSwapOutput(uint256 tokensSold, uint256 minTokensBought, uint256 minEthBought, uint256 deadline, address tokenAddr) external returns (uint256  tokensBought){
        require(address(outputToken) == tokenAddr, "token not supported");
        require(minTokensBought <= tokensSold, "not enough tokens supplied");
        require(inputToken.transferFrom(msg.sender, address(this), tokensSold),"couldnt transfer input token");

        uint256 purchasedTokens = tokensSold;
        require(purchasedTokens >= minTokensBought,"couldnt get minTokensBought");
        require(outputToken.transfer(msg.sender, purchasedTokens),"couldnt buy token");
        return purchasedTokens;
    }
}