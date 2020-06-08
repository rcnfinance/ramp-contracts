pragma solidity ^0.6.6;

import "./../interfaces/ITokenConverter.sol";
import "./../interfaces/uniswapV2/IUniswapV2Router01.sol";
import "./../utils/SafeERC20.sol";
import "../interfaces/IERC20.sol";
import "../utils/Ownable.sol";


/// @notice proxy between ConverterRamp and Uniswap V2
///         accepts tokens and ether, converts these to the desired token,
///         and makes approve calls to allow the recipient to transfer those
///         tokens from the contract.
/// @author Victor Fage (victorfage@gmail.com)
contract UniswapV2Converter is ITokenConverter, Ownable {
    using SafeERC20 for IERC20;

    /// @notice address to identify operations with ETH
    IERC20 constant internal ETH_TOKEN_ADDRESS = IERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    IUniswapV2Router01 public router;

    constructor (IUniswapV2Router01 _router) public {
        router = _router;
    }

    function convertFrom(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _fromAmount,
        uint256 _minReceive
    ) override external payable returns (uint256 received) {
        address[] memory path = handlePath(_fromToken, _toToken);

        uint[] memory amounts;

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // Convert ETH to TOKEN
            // and send directly to msg.sender
            require(msg.value == _fromAmount, "Sent eth is not enought");

            amounts = router.swapExactETHForTokens.value(
                _fromAmount
            )(
                _minReceive,
                path,
                msg.sender,
                uint(-1)
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
                    uint(-1)
                );
            } else {
                // Convert TOKENA to ETH
                // and send it to this contract
                amounts = router.swapExactTokensForTokens(
                    _fromAmount,
                    _minReceive,
                    path,
                    msg.sender,
                    uint(-1)
                );
            }
        }

        received = amounts[1];
    }

    function convertTo(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _toAmount,
        uint256 _maxSpend
    ) override external payable returns (uint256 spent) {
        address[] memory path = handlePath(_fromToken, _toToken);

        uint256[] memory amounts;

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // Convert ETH to TOKEN
            // and send directly to msg.sender
            require(msg.value == _maxSpend, "Sent eth is not enought");

            amounts = router.swapETHForExactTokens.value(
                _maxSpend
            )(
                _toAmount,
                path,
                msg.sender,
                uint(-1)
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
                    uint(-1)
                );
            } else {
                // Convert TOKEN to ETH
                // and send directly to msg.sender
                amounts = router.swapTokensForExactTokens(
                    _toAmount,
                    _maxSpend,
                    path,
                    msg.sender,
                    uint(-1)
                );
            }
        }

        spent = amounts[0];
    }

    function getPriceConvertFrom(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _fromAmount
    ) override external view returns (uint256 toAmount) {
        address[] memory path = handlePath(_fromToken, _toToken);

        uint256[] memory amounts = router.getAmountsOut(_fromAmount, path);
        toAmount = amounts[1];
    }

    function getPriceConvertTo(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _toAmount
    ) override external view returns (uint256 fromAmount) {
        address[] memory path = handlePath(_fromToken, _toToken);

        uint256[] memory amounts = router.getAmountsIn(_toAmount, path);
        fromAmount = amounts[0];
    }

    function _approveOnlyOnce(
        IERC20 _token,
        address _spender,
        uint256 _amount
    ) private {
        uint256 allowance = _token.allowance(address(this), _spender);
        if (allowance < _amount) {
            if (allowance != 0) {
                _token.clearApprove(_spender);
            }

            _token.approve(_spender, uint(-1));
        }
    }

    function handlePath(IERC20 _fromToken, IERC20 _toToken) private view returns(address[] memory path) {
        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // From ETH
            path[0] = router.WETH();
            path[1] = address(_toToken);
        } else {
            if (_toToken == ETH_TOKEN_ADDRESS) {
                // To ETH
                path[0] = address(_fromToken);
                path[1] = router.WETH();
            } else {
                path[0] = address(_fromToken);
                path[1] = address(router.WETH());
                path[2] = address(_toToken);
            }
        }  
        return path;
    }

    function emergencyWithdraw(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        _token.transfer(_to, _amount);
    }

    receive() external payable {
        // solhint-disable-next-line
        require(tx.origin != msg.sender, "uniswap-converter: send eth rejected");
    }
}