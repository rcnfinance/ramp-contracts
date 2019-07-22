pragma solidity ^0.5.10;

import "./../../common/ERC165.sol";
import "../../common/BytesUtils.sol";

contract RateOracle is IERC165 {
    uint256 public constant VERSION = 5;
    bytes4 internal constant RATE_ORACLE_INTERFACE = 0xa265d8e0;

    constructor() internal {}

    /**
        3 or 4 letters symbol of the currency, Ej: ETH
    */
    function symbol() external view returns (string memory);

    /**
        Descriptive name of the currency, Ej: Ethereum
    */
    function name() external view returns (string memory);

    /**
        The number of decimals of the currency represented by this Oracle,
            it should be the most common number of decimal places
    */
    function decimals() external view returns (uint256);

    /**
        The base token on which the sample is returned
            should be the RCN Token address.
    */
    function token() external view returns (address);

    /**
        The currency symbol encoded on a UTF-8 Hex
    */
    function currency() external view returns (bytes32);

    /**
        The name of the Individual or Company in charge of this Oracle
    */
    function maintainer() external view returns (string memory);

    /**
        Returns the url where the oracle exposes a valid "oracleData" if needed
    */
    function url() external view returns (string memory);

    /**
        Returns a sample on how many token() are equals to how many currency()
    */
    function readSample(bytes calldata _data) external returns (uint256 _tokens, uint256 _equivalent);
}

contract TestRateOracle is BytesUtils, ERC165, RateOracle {
    uint256 public constant VERSION = 5;
    bytes4 internal constant RATE_ORACLE_INTERFACE = 0xa265d8e0;

    constructor() public {
        _registerInterface(RATE_ORACLE_INTERFACE);
    }

    function symbol() external view returns (string memory) {}

    function name() external view returns (string memory) {}

    function decimals() external view returns (uint256) {}

    function token() external view returns (address) {}

    function currency() external view returns (bytes32) {}

    function maintainer() external view returns (string memory) {}

    function url() external view returns (string memory) {}

    function encodeRate(
        uint128 _tokens,
        uint128 _equivalent
    ) external pure returns (bytes memory) {
        return abi.encodePacked(_tokens, _equivalent);
    }

    function readSample(bytes calldata _data) external returns (uint256 tokens, uint256 equivalent) {
        (bytes32 btokens, bytes32 bequivalent) = decode(_data, 16, 16);
        tokens = uint256(btokens);
        equivalent = uint256(bequivalent);
    }
}