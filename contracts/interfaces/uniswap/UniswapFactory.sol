pragma solidity 0.5.12;

import "./UniswapExchange.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


/// https://docs.uniswap.io/smart-contract-integration/interface
contract UniswapFactory {
    /// Public Variables
    address public exchangeTemplate;
    uint256 public tokenCount;
    /// Create Exchange
    function createExchange(IERC20 token) external returns (UniswapExchange exchange);
    /// Get Exchange and Token Info
    function getExchange(IERC20 token) external view returns (UniswapExchange exchange);
    function getToken(address exchange) external view returns (IERC20 token);
    function getTokenWithId(uint256 tokenId) external view returns (IERC20 token);
    /// Never use
    function initializeFactory(address template) external;
}