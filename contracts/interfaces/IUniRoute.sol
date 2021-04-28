pragma solidity ^0.6.6;

interface IUniRoute {
    function getPath(address _fromToken, address _toToken) external view returns(address[] memory path);
    function setPath(address _fromToken, address _toToken, address[] calldata path) external;
}
