pragma solidity ^0.6.6;

import "./ILoanManager.sol";


interface ICosigner {
    function cost(
        ILoanManager engine,
        bytes32 index,
        bytes calldata data,
        bytes calldata oracleData
    ) external view returns (uint256);
}
