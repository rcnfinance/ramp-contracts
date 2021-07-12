pragma solidity ^0.8.0;


interface ICosigner {
    function cost(
        address engine,
        uint256 index,
        bytes calldata data,
        bytes calldata oracleData
    ) external view returns (uint256);
}
