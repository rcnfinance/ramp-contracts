pragma solidity ^0.6.6;

import "./IRateOracle.sol";


interface IDebtEngine {
    enum Status {
        NULL,
        ONGOING,
        PAID,
        DESTROYED, // Deprecated, used in basalt version
        ERROR
    }

    function pay(
        bytes32 _id,
        uint256 _amountToPay,
        address _origin,
        bytes calldata _oracleData
    ) external returns (uint256 paid, uint256 paidToken, uint256 burnToken);

    function payToken(
        bytes32 id,
        uint256 amount,
        address origin,
        bytes calldata oracleData
    ) external returns (uint256 paid, uint256 paidToken, uint256 burnToken);

    function withdraw(
        bytes32 _id,
        address _to
    ) external returns (uint256 amount);

    function withdrawPartial(
        bytes32 _id,
        address _to,
        uint256 _amount
    ) external returns (bool success);

    function withdrawBatch(
        bytes32[] calldata _ids,
        address _to
    ) external returns (uint256 total);

    function transferFrom(address _from, address _to, uint256 _assetId) external;

    function getStatus(bytes32 _id) external view returns (Status);

    function toFee(bytes32 _id, uint256 _amount) external view returns (uint256 feeAmount);
}
