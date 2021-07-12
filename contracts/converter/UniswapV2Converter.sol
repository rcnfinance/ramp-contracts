pragma solidity ^0.8.0;

import "./../interfaces/ITokenConverter.sol";
import "./../interfaces/uniswapV2/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/// @notice proxy between ConverterRamp and Uniswap V2
///         accepts tokens and ether, converts these to the desired token,
///         and makes approve calls to allow the recipient to transfer those
///         tokens from the contract.
/// @author Victor Fage (victorfage@gmail.com)
contract UniswapV2Converter is ITokenConverter, Ownable {
    using SafeERC20 for IERC20;

    event SetRouter(IUniswapV2Router02 _router);

    /// @dev address to identify operations with ETH
    IERC20 constant internal ETH_TOKEN_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    IUniswapV2Router02 public router;

    constructor (IUniswapV2Router02 _router) {
        router = _router;
    }

    function setRouter(IUniswapV2Router02 _router) external onlyOwner {
        router = _router;

        emit SetRouter(_router);
    }

    function convertFrom(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _fromAmount,
        uint256 _minReceive
    ) override external payable returns (uint256 received) {
        address[] memory path = _handlePath(_fromToken, _toToken);
        uint[] memory amounts;

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // Convert ETH to TOKEN
            // and send directly to msg.sender
            require(msg.value == _fromAmount, "Sent eth is not enought");

            amounts = router.swapExactETHForTokens{
                value: _fromAmount
            }(
                _minReceive,
                path,
                msg.sender,
                type(uint256).max
            );
        } else {
            require(msg.value == 0, "Method is not payable");
            require(_fromToken.transferFrom(msg.sender, address(this), _fromAmount), "Error pulling tokens");

            _approveOnlyOnce(_fromToken, address(router), _fromAmount);

            if (_toToken == ETH_TOKEN_ADDRESS) {
                // Convert TOKEN to ETH
                // and send directly to msg.sender
                amounts = router.swapExactTokensForETH(
                    _fromAmount,
                    _minReceive,
                    path,
                    msg.sender,
                    type(uint256).max
                );
            } else {
                // Convert TOKENA to ETH
                // and send it to this contract
                amounts = router.swapExactTokensForTokens(
                    _fromAmount,
                    _minReceive,
                    path,
                    msg.sender,
                    type(uint256).max
                );
            }
        }

        received = amounts[amounts.length - 1];

        require(received >= _minReceive, "_received is not enought");
    }

    function convertTo(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _toAmount,
        uint256 _maxSpend
    ) override external payable returns (uint256 spent) {
        address[] memory path = _handlePath(_fromToken, _toToken);
        uint256[] memory amounts;

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // Convert ETH to TOKEN
            // and send directly to msg.sender
            require(msg.value == _maxSpend, "Sent eth is not enought");

            amounts = router.swapETHForExactTokens{
                value: _maxSpend
            }(
                _toAmount,
                path,
                msg.sender,
                type(uint256).max
            );
        } else {
            require(msg.value == 0, "Method is not payable");
            require(_fromToken.transferFrom(msg.sender, address(this), _maxSpend), "Error pulling tokens");

            _approveOnlyOnce(_fromToken, address(router), _maxSpend);

            if (_toToken == ETH_TOKEN_ADDRESS) {
                // Convert TOKEN to ETH
                // and send directly to msg.sender
                amounts = router.swapTokensForExactETH(
                    _toAmount,
                    _maxSpend,
                    path,
                    msg.sender,
                    type(uint256).max
                );
            } else {
                // Convert TOKEN to ETH
                // and send directly to msg.sender
                amounts = router.swapTokensForExactTokens(
                    _toAmount,
                    _maxSpend,
                    path,
                    msg.sender,
                    type(uint256).max
                );
            }
        }

        spent = amounts[0];

        require(spent <= _maxSpend, "_maxSpend exceed");
        if (spent < _maxSpend) {
            _transfer(_fromToken, payable(msg.sender), _maxSpend - spent);
        }
    }

    function getPriceConvertFrom(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _fromAmount
    ) override external view returns (uint256 toAmount) {
        address[] memory path = _handlePath(_fromToken, _toToken);
        uint256[] memory amounts = router.getAmountsOut(_fromAmount, path);

        toAmount = amounts[amounts.length - 1];
    }

    function getPriceConvertTo(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _toAmount
    ) override external view returns (uint256 fromAmount) {
        address[] memory path = _handlePath(_fromToken, _toToken);
        uint256[] memory amounts = router.getAmountsIn(_toAmount, path);

        fromAmount = amounts[0];
    }

    function _approveOnlyOnce(
        IERC20 _token,
        address _spender,
        uint256 _amount
    ) private {
        if (_token.allowance(address(this), _spender) < _amount) {
            _token.safeIncreaseAllowance(_spender, type(uint256).max);
        }
    }

    function _handlePath(IERC20 _fromToken, IERC20 _toToken) private view returns(address[] memory path) {
        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // From ETH
            path = new address[](2);
            path[0] = router.WETH();
            path[1] = address(_toToken);
        } else {
            if (_toToken == ETH_TOKEN_ADDRESS) {
                // To ETH
                path = new address[](2);
                path[0] = address(_fromToken);
                path[1] = router.WETH();
            } else {
                // Token To Token
                path = new address[](3);
                path[0] = address(_fromToken);
                path[1] = router.WETH();
                path[2] = address(_toToken);
            }
        }
        return path;
    }

    function _transfer(
        IERC20 _token,
        address payable _to,
        uint256 _amount
    ) private {
        if (_token == ETH_TOKEN_ADDRESS) {
            _to.transfer(_amount);
        } else {
            require(_token.transfer(_to, _amount), "error sending tokens");
        }
    }

    function emergencyWithdraw(
        IERC20 _token,
        address payable _to,
        uint256 _amount
    ) external onlyOwner {
        _transfer(_token, _to, _amount);
    }

    receive() external payable {
        // solhint-disable-next-line
        require(tx.origin != msg.sender, "uniswap-converter: send eth rejected");
    }
}