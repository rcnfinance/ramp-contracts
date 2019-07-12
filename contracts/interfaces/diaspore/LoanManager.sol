pragma solidity 0.5.10;

import 'openzeppelin-solidity/contracts/token/ERC20/IERC20.sol';


contract LoanManager {
    IERC20 public token;

    function getCurrency(uint256 _id) external view returns (bytes32);
    function getAmount(uint256 _id) external view returns (uint256);
    function getOracle(uint256 _id) external view returns (address);

    function settleLend(
        bytes memory _requestData,
        bytes memory _loanData,
        address _cosigner,
        uint256 _maxCosignerCost,
        bytes memory _cosignerData,
        bytes memory _oracleData,
        bytes memory _creatorSig,
        bytes memory _borrowerSig
    ) public returns (bytes32 id);

    function lend(
        bytes32 _id,
        bytes memory _oracleData,
        address _cosigner,
        uint256 _cosignerLimit,
        bytes memory _cosignerData
    ) public returns (bool);

}
