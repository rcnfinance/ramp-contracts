pragma solidity ^0.5.10;

import 'openzeppelin-solidity/contracts/token/ERC20/IERC20.sol';
import './../../common/ERC721Base.sol';

contract TestDebtEngine is ERC721Base {

    event Paid(
        bytes32 indexed _id,
        address _sender,
        address _origin,
        uint256 _requested,
        uint256 _requestedTokens,
        uint256 _paid,
        uint256 _tokens
    );

    IERC20 public token;

    constructor (
        IERC20 _token
    ) public ERC721Base("RCN Debt Record", "RDR") {
        token = _token;

        // Sanity checks
        require(address(_token).isContract(), "Token should be a contract");
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

    function pay(
        bytes32 _id,
        uint256 _amount,
        address _origin,
        bytes calldata _oracleData
    ) external returns (uint256 paid, uint256 paidToken) {
        
        // Pull tokens from payer
        require(token.transferFrom(msg.sender, address(this), _amount), "Error pulling payment tokens");

        // Emit pay event
        emit Paid({
            _id: _id,
            _sender: msg.sender,
            _origin: _origin,
            _requested: _amount,
            _requestedTokens: 0,
            _paid: paid,
            _tokens: paidToken
        });

    }
}