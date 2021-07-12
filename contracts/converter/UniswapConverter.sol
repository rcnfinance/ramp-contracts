pragma solidity ^0.8.0;

import "../interfaces/ITokenConverter.sol";
import "../interfaces/uniswap/IUniswapFactory.sol";
import "../interfaces/uniswap/IUniswapExchange.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/// @notice proxy between ConverterRamp and Uniswap
///         accepts tokens and ether, converts these to the desired token,
///         and makes approve calls to allow the recipient to transfer those
///         tokens from the contract.
/// @author Joaquin Pablo Gonzalez (jpgonzalezra@gmail.com) & Agustin Aguilar (agusxrun@gmail.com)
contract UniswapConverter is ITokenConverter, Ownable {
    using SafeERC20 for IERC20;

    /// @dev address to identify operations with ETH
    IERC20 constant internal ETH_TOKEN_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @notice registry of ERC20 tokens that have been added to the system
    ///         and the exchange to which they are associated.
    IUniswapFactory immutable public factory;

    constructor (address _uniswapFactory) {
        factory = IUniswapFactory(_uniswapFactory);
    }

    function convertFrom(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _fromAmount,
        uint256 _minReceive
    ) override external payable returns (uint256 _received) {
        _pull(_fromToken, _fromAmount);

        IUniswapFactory _factory = factory;

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // Convert ETH to TOKEN
            // and send directly to msg.sender
            _received = _factory.getExchange(_toToken).ethToTokenTransferInput{
                value: _fromAmount
            }(
                1,
                type(uint256).max,
                msg.sender
            );
        } else if (_toToken == ETH_TOKEN_ADDRESS) {
            // Load Uniswap exchange
            IUniswapExchange exchange = _factory.getExchange(_fromToken);
            // Convert TOKEN to ETH
            // and send directly to msg.sender
            _approveOnlyOnce(_fromToken, address(exchange), _fromAmount);
            _received = exchange.tokenToEthTransferInput(
                _fromAmount,
                1,
                type(uint256).max,
                msg.sender
            );
        } else {
            // Load Uniswap exchange
            IUniswapExchange exchange = _factory.getExchange(_fromToken);
            // Convert TOKENA to ETH
            // and send it to this contract
            _approveOnlyOnce(_fromToken, address(exchange), _fromAmount);
            _received = exchange.tokenToTokenTransferInput(
                _fromAmount,
                1,
                1,
                type(uint256).max,
                msg.sender,
                address(_toToken)
            );
        }

        require(_received >= _minReceive, "_received is not enought");
    }

    function convertTo(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _toAmount,
        uint256 _maxSpend
    ) override external payable returns (uint256 _spent) {
        _pull(_fromToken, _maxSpend);

        IUniswapFactory _factory = factory;

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // Convert ETH to TOKEN
            // and send directly to msg.sender
            _spent = _factory.getExchange(_toToken).ethToTokenTransferOutput{
                value: _maxSpend
            }(
                _toAmount,
                type(uint256).max,
                msg.sender
            );
        } else if (_toToken == ETH_TOKEN_ADDRESS) {
            // Load Uniswap exchange
            IUniswapExchange exchange = _factory.getExchange(_fromToken);
            // Convert TOKEN to ETH
            // and send directly to msg.sender
            _approveOnlyOnce(_fromToken, address(exchange), _maxSpend);
            _spent = exchange.tokenToEthTransferOutput(
                _toAmount,
                _maxSpend,
                type(uint256).max,
                msg.sender
            );
        } else {
            // Load Uniswap exchange
            IUniswapExchange exchange = _factory.getExchange(_fromToken);
            // Convert TOKEN to ETH
            // and send directly to msg.sender
            _approveOnlyOnce(_fromToken, address(exchange), _maxSpend);
            _spent = exchange.tokenToTokenTransferOutput(
                _toAmount,
                _maxSpend,
                type(uint256).max,
                type(uint256).max,
                msg.sender,
                address(_toToken)
            );
        }

        require(_spent <= _maxSpend, "_maxSpend exceed");
        if (_spent < _maxSpend) {
            _transfer(_fromToken, payable(msg.sender), _maxSpend - _spent);
        }
    }

    function getPriceConvertFrom(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _fromAmount
    ) override external view returns (uint256 _receive) {
        IUniswapFactory _factory = factory;

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // ETH -> TOKEN convertion
            _receive = _factory.getExchange(_toToken).getEthToTokenInputPrice(_fromAmount);
        } else if (_toToken == ETH_TOKEN_ADDRESS) {
            // TOKEN -> ETH convertion
            _receive = _factory.getExchange(_fromToken).getTokenToEthInputPrice(_fromAmount);
        } else {
            // TOKENA -> TOKENB convertion
            //   equals to: TOKENA -> ETH -> TOKENB
            uint256 ethBought = _factory.getExchange(_fromToken).getTokenToEthInputPrice(_fromAmount);
            _receive = _factory.getExchange(_toToken).getEthToTokenInputPrice(ethBought);
        }
    }

    function getPriceConvertTo(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _toAmount
    ) override external view returns (uint256 _spend) {
        IUniswapFactory _factory = factory;

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // ETH -> TOKEN convertion
            _spend = _factory.getExchange(_toToken).getEthToTokenOutputPrice(_toAmount);
        } else if (_toToken == ETH_TOKEN_ADDRESS) {
            // TOKEN -> ETH convertion
            _spend = _factory.getExchange(_fromToken).getTokenToEthOutputPrice(_toAmount);
        } else {
            // TOKENA -> TOKENB convertion
            //   equals to: TOKENA -> ETH -> TOKENB
            uint256 ethSpend = _factory.getExchange(_toToken).getEthToTokenOutputPrice(_toAmount);
            _spend = _factory.getExchange(_fromToken).getTokenToEthOutputPrice(ethSpend);
        }
    }

    function _pull(
        IERC20 _token,
        uint256 _amount
    ) private {
        if (_token == ETH_TOKEN_ADDRESS) {
            require(msg.value == _amount, "sent eth is not enought");
        } else {
            require(msg.value == 0, "method is not payable");
            require(_token.transferFrom(msg.sender, address(this), _amount), "error pulling tokens");
        }
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

    function _approveOnlyOnce(
        IERC20 _token,
        address _spender,
        uint256 _amount
    ) private {
        if (_token.allowance(address(this), _spender) < _amount) {
            _token.safeIncreaseAllowance(_spender, type(uint256).max);
        }
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
