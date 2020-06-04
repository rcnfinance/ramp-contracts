pragma solidity ^0.6.6;

import "./IUniswapExchange.sol";
import "../IERC20.sol";


/// https://docs.uniswap.io/smart-contract-integration/interface
abstract contract IUniswapFactory {
    /// Public Variables
    address public exchangeTemplate;
    uint256 public tokenCount;
    /// Create Exchange
    function createExchange(IERC20 token) virtual external returns (IUniswapExchange exchange);
    /// Get Exchange and Token Info
    function getExchange(IERC20 token) virtual external view returns (IUniswapExchange exchange);
    function getToken(address exchange) virtual external view returns (IERC20 token);
    function getTokenWithId(uint256 tokenId) virtual external view returns (IERC20 token);
    /// Never use
    function initializeFactory(address template) virtual external;
}