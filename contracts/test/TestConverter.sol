pragma solidity ^0.6.6;

import "../interfaces/ITokenConverter.sol";
import "../interfaces/uniswapV2/IUniswapV2Router02.sol";
import "../utils/SafeERC20.sol";
import "../interfaces/IERC20.sol";


contract TestConverter is ITokenConverter{
    using SafeERC20 for IERC20;

    IERC20 constant private ETH_TOKEN_ADDRESS = IERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    uint256 public customFromAmount;
    uint256 public customToAmount;

    function setCustomData(uint256 _customFromAmount, uint256 _customToAmount) external {
        customFromAmount = _customFromAmount;
        customToAmount = _customToAmount;
    }

    function convertFrom(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _fromAmount,
        uint256
    ) override external payable returns (uint256) {
        if (_fromToken != ETH_TOKEN_ADDRESS) {
            require(_fromToken.transferFrom(msg.sender, address(this), customFromAmount), "convertFrom: error taking tokens");
        } else {
            require(msg.value == _fromAmount, "convertFrom: error receive ETH");
            msg.sender.transfer(_fromAmount - customFromAmount);
        }

        require(_toToken.transfer(msg.sender, customToAmount), "convertFrom: error sending tokens");
    }

    function convertTo(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256,
        uint256 _maxSpend
    ) override external payable returns (uint256) {
        if (_fromToken != ETH_TOKEN_ADDRESS) {
            require(_fromToken.transferFrom(msg.sender, address(this), customFromAmount), "convertTo: error taking tokens");
        } else {
            require(msg.value == _maxSpend, "convertTo: error receive ETH");
            msg.sender.transfer(_maxSpend - customFromAmount);
        }

        require(_toToken.transfer(msg.sender, customToAmount), "convertTo: error sending tokens");
    }

    function getPriceConvertFrom(
        IERC20,
        IERC20,
        uint256 _fromAmount
    ) override external view returns (uint256) {
        return customToAmount == 0 ? _fromAmount : customToAmount;
    }

    function getPriceConvertTo(
        IERC20,
        IERC20,
        uint256 _toAmount
    ) override external view returns (uint256) {
        return customFromAmount == 0 ? _toAmount : customFromAmount;
    }

    receive() external payable { }
}