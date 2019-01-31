pragma solidity 0.5.0;


interface DebtEngine {

    function pay(
        bytes32 _id,
        uint256 _amount,
        address _origin,
        bytes calldata _oracleData
    ) external returns (uint256 paid, uint256 paidToken);

    function transferFrom(address _from, address _to, uint256 _assetId) external;
}
