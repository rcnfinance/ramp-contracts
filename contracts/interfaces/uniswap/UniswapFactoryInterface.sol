pragma solidity 0.5.10;

contract UniswapFactoryInterface {
    function getExchange(address token) external view returns (address exchange);
}