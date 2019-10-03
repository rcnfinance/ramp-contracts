pragma solidity ^0.5.11;

import "./Model.sol";
import "../RateOracle.sol";


interface DebtEngine {
    function debts(
        bytes32 _id
    ) external view returns(
        bool error,
        uint128 balance,
        Model model,
        address creator,
        RateOracle oracle
    );

    function create(
        Model _model,
        address _owner,
        address _oracle,
        bytes calldata _data
    ) external returns (bytes32 id);

    function create2(
        Model _model,
        address _owner,
        address _oracle,
        uint256 _salt,
        bytes calldata _data
    ) external returns (bytes32 id);

    function create3(
        Model _model,
        address _owner,
        address _oracle,
        uint256 _salt,
        bytes calldata _data
    ) external returns (bytes32 id);

    function buildId(
        address _creator,
        uint256 _nonce
    ) external view returns (bytes32);

    function buildId2(
        address _creator,
        address _model,
        address _oracle,
        uint256 _salt,
        bytes calldata _data
    ) external view returns (bytes32);

    function buildId3(
        address _creator,
        uint256 _salt
    ) external view returns (bytes32);

    function pay(
        bytes32 _id,
        uint256 _amount,
        address _origin,
        bytes calldata _oracleData
    ) external returns (uint256 paid, uint256 paidToken);

    function payToken(
        bytes32 id,
        uint256 amount,
        address origin,
        bytes calldata oracleData
    ) external returns (uint256 paid, uint256 paidToken);

    function payBatch(
        bytes32[] calldata _ids,
        uint256[] calldata _amounts,
        address _origin,
        address _oracle,
        bytes calldata _oracleData
    ) external returns (uint256[] memory paid, uint256[] memory paidTokens);

    function payTokenBatch(
        bytes32[] calldata _ids,
        uint256[] calldata _tokenAmounts,
        address _origin,
        address _oracle,
        bytes calldata _oracleData
    ) external returns (uint256[] memory paid, uint256[] memory paidTokens);

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

    function getStatus(bytes32 _id) external view returns (uint256);
}
