pragma solidity ^0.6.6;

import "../IERC20.sol";
import "./IDebtEngine.sol";
import "./IRateOracle.sol";


interface ILoanManager {
    function token() external view returns (IERC20);

    function debtEngine() external view returns (IDebtEngine);
    function getCurrency(uint256 _id) external view returns (bytes32);
    function getAmount(uint256 _id) external view returns (uint256);
    function getAmount(bytes32 _id) external view returns (uint256);
    function getOracle(bytes32 _id) external view returns (IRateOracle);
    function getClosingObligation(bytes32 _id) external view returns (uint256 amount, uint256 fee);

    function settleLend(
        bytes calldata _requestData,
        bytes calldata _loanData,
        address _cosigner,
        uint256 _maxCosignerCost,
        bytes calldata _cosignerData,
        bytes calldata _oracleData,
        bytes calldata _creatorSig,
        bytes calldata _borrowerSig
    ) external returns (bytes32 id);

    function lend(
        bytes32 _id,
        bytes calldata _oracleData,
        address _cosigner,
        uint256 _cosignerLimit,
        bytes calldata _cosignerData,
        bytes calldata _callbackData
    ) external returns (bool);
}
