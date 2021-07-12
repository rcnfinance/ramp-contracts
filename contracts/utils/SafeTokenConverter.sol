pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ITokenConverter.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


library SafeTokenConverter {
    IERC20 constant private ETH_TOKEN_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    using SafeERC20 for IERC20;

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
            _fromToken.safeApprove(address(_converter), _fromAmount);
            _converter.convertFrom(
                _fromToken,
                _toToken,
                _fromAmount,
                _minReceive
            );

            _fromToken.safeApprove(address(_converter), 0);
        }

        _received = _selfBalance(_toToken) - prevBalance;
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
            _fromToken.safeApprove(address(_converter), _maxSpend);
            _converter.convertTo(
                _fromToken,
                _toToken,
                _toAmount,
                _maxSpend
            );

            _fromToken.safeApprove(address(_converter), 0);
        }

        _spend = prevFromBalance - _selfBalance(_fromToken);
        require(_spend <= _maxSpend, "_maxSpend exceeded");
        require(_selfBalance(_toToken) - prevToBalance >= _toAmount, "_toAmount not received");
    }

    function _selfBalance(IERC20 _token) private view returns (uint256) {
        if (_token == ETH_TOKEN_ADDRESS) {
            return address(this).balance;
        } else {
            return _token.balanceOf(address(this));
        }
    }
}
