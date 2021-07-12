pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IDebtEngine.sol";


interface ILoanManager {
    function token() external view returns (IERC20);

    function debtEngine() external view returns (IDebtEngine);
    function getCurrency(uint256 _id) external view returns (bytes32);
    function getAmount(uint256 _id) external view returns (uint256);
    function getAmount(bytes32 _id) external view returns (uint256);
    function getOracle(uint256 _id) external view returns (address);

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
