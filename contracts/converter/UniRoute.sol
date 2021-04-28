

pragma solidity ^0.6.6;

import "../utils/Ownable.sol";
import "../interfaces/IUniRoute.sol";

contract UniRoute is Ownable, IUniRoute {
    mapping(bytes32 => address[]) public paths;

    function setPath(address _fromToken, address _toToken, address[] calldata _path) external override onlyOwner { 
        require(_fromToken != _toToken, "UniRoute: IDENTICAL_ADDRESSES");
        bytes32 id = keccak256(abi.encodePacked(_fromToken, _toToken));
        paths[id] = _path;
    }
    
    function getPath(address _fromToken, address _toToken) external view override returns(address[] memory path) {
        bytes32 id = keccak256(abi.encodePacked(_fromToken, _toToken));
        return paths[id];
    }
        
}

