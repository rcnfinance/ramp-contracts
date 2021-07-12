pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/rcn/ICosigner.sol";
import "./interfaces/rcn/IDebtEngine.sol";
import "./interfaces/rcn/ILoanManager.sol";
import "./interfaces/ITokenConverter.sol";
import "./interfaces/rcn/IRateOracle.sol";

import "./utils/SafeTokenConverter.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./utils/Math.sol";


/// @title  Converter Ramp
/// @notice for conversion between different assets, use ITokenConverter
///         contract as abstract layer for convert different assets.
/// @dev All function calls are currently implemented without side effects
contract ConverterRamp is Ownable {
    using SafeTokenConverter for ITokenConverter;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice address to identify operations with ETH
    address public constant ETH_ADDRESS = address(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    event Return(address _token, address _to, uint256 _amount);
    event ReadedOracle(address _oracle, uint256 _tokens, uint256 _equivalent);

    IDebtEngine immutable public debtEngine;
    ILoanManager immutable public loanManager;
    IERC20 immutable public token;

    constructor(ILoanManager _loanManager) public {
        loanManager = _loanManager;
        token = _loanManager.token();
        debtEngine = _loanManager.debtEngine();
    }

    function pay(
        ITokenConverter _converter,
        IERC20 _fromToken,
        uint256 _payAmount,
        uint256 _maxSpend,
        bytes32 _requestId,
        bytes calldata _oracleData
    ) external payable {
        IDebtEngine _debtEngine = debtEngine;

        // Get amount required, in RCN, for payment
        uint256 amount = getRequiredRcnPay(
            _debtEngine,
            _requestId,
            _payAmount,
            _oracleData
        );

        // Pull funds from sender
        IERC20 _token = token;
        _pullConvertAndReturnExtra(
            _converter,
            _fromToken,
            _token,
            amount,
            _maxSpend
        );

        // Pay the loan the debtEngine is trusted so we can approve it only once
        _approveOnlyOnce(_token, address(_debtEngine), amount);

        // Execute the payment
        (, uint256 paidToken) = _debtEngine.payToken(_requestId, amount, msg.sender, _oracleData);

        // Convert any extra RCN and send it back it should not be reachable
        if (paidToken < amount) {
            _convertAndReturn(
                _converter,
                _token,
                _fromToken,
                amount - paidToken
            );
        }
    }

    function lend(
        ITokenConverter _converter,
        IERC20 _fromToken,
        uint256 _maxSpend,
        ICosigner _cosigner,
        uint256 _cosignerLimitCost,
        bytes32 _requestId,
        bytes memory _oracleData,
        bytes memory _cosignerData,
        bytes memory _callbackData
    ) public payable {
        ILoanManager _loanManager = loanManager;

        // Get required RCN for lending the loan
        uint256 amount = getRequiredRcnLend(
            _loanManager,
            _cosigner,
            _requestId,
            _oracleData,
            _cosignerData
        );

        IERC20 _token = token;
        _pullConvertAndReturnExtra(
            _converter,
            _fromToken,
            _token,
            amount,
            _maxSpend
        );

        // Approve token to loan manager only once the loan manager is trusted
        _approveOnlyOnce(_token, address(_loanManager), amount);

        _loanManager.lend(
            _requestId,
            _oracleData,
            address(_cosigner),
            _cosignerLimitCost,
            _cosignerData,
            _callbackData
        );

        // Transfer loan to the msg.sender
        debtEngine.transferFrom(address(this), msg.sender, uint256(_requestId));
    }

    function getLendCost(
        ITokenConverter _converter,
        IERC20 _fromToken,
        ICosigner _cosigner,
        bytes32 _requestId,
        bytes calldata _oracleData,
        bytes calldata _cosignerData
    ) external returns (uint256) {
        uint256 amountRcn = getRequiredRcnLend(
            loanManager,
            _cosigner,
            _requestId,
            _oracleData,
            _cosignerData
        );

        return _converter.getPriceConvertTo(
            _fromToken,
            token,
            amountRcn
        );
    }

    /// @notice returns how much RCN is required for a given pay
    function getPayCost(
        ITokenConverter _converter,
        IERC20 _fromToken,
        bytes32 _requestId,
        uint256 _amount,
        bytes calldata _oracleData
    ) external returns (uint256) {
        uint256 amountRcn = getRequiredRcnPay(
            debtEngine,
            _requestId,
            _amount,
            _oracleData
        );

        return _converter.getPriceConvertTo(
            _fromToken,
            token,
            amountRcn
        );
    }

    /// @notice returns how much RCN is required for a given lend
    function getRequiredRcnLend(
        ILoanManager _loanManager,
        ICosigner _lenderCosignerAddress,
        bytes32 _requestId,
        bytes memory _oracleData,
        bytes memory _cosignerData
    ) internal returns (uint256) {
        // Load request amount
        uint256 amount = loanManager.getAmount(_requestId);

        // If loan has a cosigner, sum the cost
        if (_lenderCosignerAddress != ICosigner(address(0))) {
            amount = amount + _lenderCosignerAddress.cost(
                address(_loanManager),
                uint256(_requestId),
                _cosignerData,
                _oracleData
            );
        }

        // Load the  Oracle rate and convert required
        address oracle = loanManager.getOracle(uint256(_requestId));

        return getCurrencyToToken(oracle, amount, _oracleData);
    }

    /// @notice returns how much RCN is required for a given pay
    function getRequiredRcnPay(
        IDebtEngine _debtEngine,
        bytes32 _requestId,
        uint256 _amount,
        bytes memory _oracleData
    ) internal returns (uint256 _result) {
        (,,IModel model,, IRateOracle oracle) = _debtEngine.debts(_requestId);

        // Load amount to pay
        uint256 amount = Math.min(
            model.getClosingObligation(_requestId),
            _amount
        );

        // Read loan oracle
        return getCurrencyToToken(address(oracle), amount, _oracleData);
    }

    /// @notice returns how much tokens for _amount currency
    /// @dev tokens and equivalents get oracle data
    function getCurrencyToToken(
        address _oracle,
        uint256 _amount,
        bytes memory _oracleData
    ) internal returns (uint256) {
        if (_oracle == address(0)) {
            return _amount;
        }

        (uint256 tokens, uint256 equivalent) = IRateOracle(_oracle).readSample(_oracleData);

        emit ReadedOracle(_oracle, tokens, equivalent);
        return (tokens * _amount).divCeil(equivalent);
    }

    function getPriceConvertTo(
        ITokenConverter _converter,
        IERC20 _fromToken,
        uint256 _amount
    ) external view returns (uint256) {
        return _converter.getPriceConvertTo(
            _fromToken,
            token,
            _amount
        );
    }

    function _convertAndReturn(
        ITokenConverter _converter,
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _amount
    ) private {
        uint256 buyBack = _converter.safeConvertFrom(
            _fromToken,
            _toToken,
            _amount,
            1
        );

        _toToken.safeTransfer(msg.sender, buyBack);
    }

    function _pullConvertAndReturnExtra(
        ITokenConverter _converter,
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _amount,
        uint256 _maxSpend
    ) private {
        // Pull limit amount from sender
        _pull(_fromToken, _maxSpend);

        uint256 spent = _converter.safeConvertTo(_fromToken, _toToken, _amount, _maxSpend);

        if (spent < _maxSpend) {
            _transfer(_fromToken, payable(msg.sender), _maxSpend - spent);
        }
    }

    function _pull(
        IERC20 _token,
        uint256 _amount
    ) private {
        if (address(_token) == ETH_ADDRESS) {
            require(msg.value == _amount, "sent eth is not enought");
        } else {
            require(msg.value == 0, "method is not payable");
            _token.safeTransferFrom(msg.sender, address(this), _amount);
        }
    }

    function _transfer(
        IERC20 _token,
        address payable _to,
        uint256 _amount
    ) private {
        if (address(_token) == ETH_ADDRESS) {
            _to.transfer(_amount);
        } else {
            _token.safeTransfer(_to, _amount);
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
        require(tx.origin != msg.sender, "ramp: send eth rejected");
    }
}
