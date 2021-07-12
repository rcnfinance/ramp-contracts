pragma solidity ^0.8.0;


/// https:///docs.uniswap.io/smart-contract-integration/interface
abstract contract IUniswapExchange {
    /// Address of ERC20 token sold on this exchange
    function tokenAddress() virtual external view returns (address token);
    /// Address of Uniswap Factory
    function factoryAddress() virtual external view returns (address factory);
    /// Provide Liquidity
    function addLiquidity(uint256 minLiquidity, uint256 maxTokens, uint256 deadline) virtual external payable returns (uint256);
    function removeLiquidity(uint256 amount, uint256 minEth, uint256 minTokens, uint256 deadline) virtual external returns (uint256, uint256);
    /// Get Prices
    function getEthToTokenInputPrice(uint256 ethSold) virtual external view returns (uint256 tokensBought);
    function getEthToTokenOutputPrice(uint256 tokensBought) virtual external view returns (uint256 ethSold);
    function getTokenToEthInputPrice(uint256 tokensSold) virtual external view returns (uint256 ethBought);
    function getTokenToEthOutputPrice(uint256 ethBought) virtual external view returns (uint256 tokensSold);
    /// Trade ETH to ERC20
    function ethToTokenSwapInput(uint256 minTokens, uint256 deadline) virtual external payable returns (uint256  tokensBought);
    function ethToTokenTransferInput(uint256 minTokens, uint256 deadline, address recipient) virtual external payable returns (uint256  tokensBought);
    function ethToTokenSwapOutput(uint256 tokensBought, uint256 deadline) virtual external payable returns (uint256  ethSold);
    function ethToTokenTransferOutput(uint256 tokensBought, uint256 deadline, address recipient) virtual external payable returns (uint256  ethSold);
    /// Trade ERC20 to ETH
    function tokenToEthSwapInput(uint256 tokensSold, uint256 minEth, uint256 deadline) virtual external returns (uint256  ethBought);
    function tokenToEthTransferInput(uint256 tokensSold, uint256 minTokens, uint256 deadline, address recipient) virtual external returns (uint256  ethBought);
    function tokenToEthSwapOutput(uint256 ethBought, uint256 maxTokens, uint256 deadline) virtual external returns (uint256  tokensSold);
    function tokenToEthTransferOutput(uint256 ethBought, uint256 maxTokens, uint256 deadline, address recipient) virtual external returns (uint256  tokensSold);
    /// Trade ERC20 to ERC20
    function tokenToTokenSwapInput(uint256 tokensSold, uint256 minTokensBought, uint256 minEthBought, uint256 deadline, address tokenAddr) virtual external returns (uint256  tokensBought);
    function tokenToTokenTransferInput(uint256 tokensSold, uint256 minTokensBought, uint256 minEthBought, uint256 deadline, address recipient, address tokenAddr) virtual external returns (uint256  tokensBought);
    function tokenToTokenSwapOutput(uint256 tokensBought, uint256 maxTokensSold, uint256 maxEthSold, uint256 deadline, address tokenAddr) virtual external returns (uint256  tokensSold);
    function tokenToTokenTransferOutput(uint256 tokensBought, uint256 maxTokensSold, uint256 maxEthSold, uint256 deadline, address recipient, address tokenAddr) virtual external returns (uint256  tokensSold);
    /// Trade ERC20 to Custom Pool
    function tokenToExchangeSwapInput(uint256 tokensSold, uint256 minTokensBought, uint256 minEthBought, uint256 deadline, address exchangeAddr) virtual external returns (uint256  tokensBought);
    function tokenToExchangeTransferInput(uint256 tokensSold, uint256 minTokensBought, uint256 minEthBought, uint256 deadline, address recipient, address exchangeAddr) virtual external returns (uint256  tokensBought);
    function tokenToExchangeSwapOutput(uint256 tokensBought, uint256 maxTokensSold, uint256 maxEthSold, uint256 deadline, address exchangeAddr) virtual external returns (uint256  tokensSold);
    function tokenToExchangeTransferOutput(uint256 tokensBought, uint256 maxTokensSold, uint256 maxEthSold, uint256 deadline, address recipient, address exchangeAddr) virtual external returns (uint256  tokensSold);
    /// ERC20 comaptibility for liquidity tokens
    bytes32 public name;
    bytes32 public symbol;
    uint256 public decimals;
    function transfer(address _to, uint256 _value) virtual external returns (bool);
    function transferFrom(address _from, address _to, uint256 value) virtual external returns (bool);
    function approve(address _spender, uint256 _value) virtual external returns (bool);
    function allowance(address _owner, address _spender) virtual external view returns (uint256);
    function balanceOf(address _owner) virtual external view returns (uint256);
    /// Never use
    function setup(address tokenAddr) virtual external;
}