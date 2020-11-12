pragma solidity ^0.6.6;

import "./DiasporeFlat.sol";


contract TestRateOracle is BytesUtils {
    function encodeRate(
        uint128 _tokens,
        uint128 _equivalent
    ) external pure returns (bytes memory) {
        return abi.encodePacked(_tokens, _equivalent);
    }

    function readSample(bytes calldata _data) external pure returns (uint256 tokens, uint256 equivalent) {
        (bytes32 btokens, bytes32 bequivalent) = decode(_data, 16, 16);
        tokens = uint256(btokens);
        equivalent = uint256(bequivalent);
    }
}