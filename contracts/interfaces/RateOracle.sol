pragma solidity 0.5.11;



/// @dev Defines the interface of a standard Diaspore RCN Oracle,
/// The contract should also implement it is ERC165 interface: 0xa265d8e0
/// @notice Each oracle can only support one currency
/// @author Agustin Aguilar
interface RateOracle {
    function readSample(bytes calldata _data) external returns (uint256 _tokens, uint256 _equivalent);
}
