pragma solidity ^0.6.6;

import "../interfaces/IERC20.sol";
import "./SafeMath.sol";
import "../interfaces/ITokenConverter.sol";
import "./SafeERC20.sol";


library SafeTokenConverter {
    IERC20 constant private ETH_TOKEN_ADDRESS = IERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    function safeConvertFrom(
        ITokenConverter _converter,
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _fromAmount,
        uint256 _minReceive
    ) internal returns (uint256 _received) {
        uint256 prevBalance = _selfBalance(_toToken);

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            _converter.convertFrom{
                value: _fromAmount
            }(
                _fromToken,
                _toToken,
                _fromAmount,
                _minReceive
            );
        } else {
            require(_fromToken.safeApprove(address(_converter), _fromAmount), "error approving converter");
            _converter.convertFrom(
                _fromToken,
                _toToken,
                _fromAmount,
                _minReceive
            );

            require(_fromToken.clearApprove(address(_converter)), "error clearing approve");
        }

        _received = _selfBalance(_toToken).sub(prevBalance);
        require(_received >= _minReceive, "_minReceived not reached");
    }

    function safeConvertTo(
        ITokenConverter _converter,
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _toAmount,
        uint256 _maxSpend
    ) internal returns (uint256 _spend) {
        uint256 prevFromBalance = _selfBalance(_fromToken);
        uint256 prevToBalance = _selfBalance(_toToken);

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            _converter.convertTo{
                value: _maxSpend
            }(
                _fromToken,
                _toToken,
                _toAmount,
                _maxSpend
            );
        } else {
            require(_fromToken.safeApprove(address(_converter), _maxSpend), "error approving converter");
            _converter.convertTo(
                _fromToken,
                _toToken,
                _toAmount,
                _maxSpend
            );

            require(_fromToken.clearApprove(address(_converter)), "error clearing approve");
        }

        _spend = prevFromBalance.sub(_selfBalance(_fromToken));
        require(_spend <= _maxSpend, "_maxSpend exceeded");
        require(_selfBalance(_toToken).sub(prevToBalance) >= _toAmount, "_toAmount not received");
    }

    function _selfBalance(IERC20 _token) private view returns (uint256) {
        if (_token == ETH_TOKEN_ADDRESS) {
            return address(this).balance;
        } else {
            return _token.balanceOf(address(this));
        }
    }
}
