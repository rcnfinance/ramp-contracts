pragma solidity ^0.6.6;


interface ICosigner {
    function cost(
        address engine,
        uint256 index,
        bytes calldata data,
        bytes calldata oracleData
    ) external view returns (uint256);
}
