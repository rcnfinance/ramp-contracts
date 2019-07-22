pragma solidity 0.5.10;


interface Cosigner {

    function cost(
        address engine,
        uint256 index,
        bytes calldata data,
        bytes calldata oracleData
    ) external view returns (uint256);

}
