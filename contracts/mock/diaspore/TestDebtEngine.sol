pragma solidity ^0.5.10;

import 'openzeppelin-solidity/contracts/token/ERC20/IERC20.sol';


contract TestDebtEngine {
    IERC20 public token;

    constructor (
        address _token
    ) public {
        token = IERC20(_token);
    }

    function buildId2(
        address _creator,
        address _model,
        address _oracle,
        uint256 _salt,
        bytes calldata _data
    ) external view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                uint8(2),
                address(this),
                _creator,
                _model,
                _oracle,
                _salt,
                _data
            )
        );
    }

    function create2(
        address _model,
        address _owner,
        address _oracle,
        uint256 _salt,
        bytes calldata _data
    ) external returns (bytes32) {
        return 0x0;
    }
}