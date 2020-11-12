pragma solidity ^0.6.6;

import "./interfaces/IERC20.sol";
import "./utils/SafeMath.sol";
import "./utils/Ownable.sol";
import "./interfaces/rcn/ICosigner.sol";
import "./interfaces/rcn/IDebtEngine.sol";
import "./interfaces/rcn/ILoanManager.sol";
import "./interfaces/ITokenConverter.sol";
import "./interfaces/rcn/IRateOracle.sol";
import "./utils/SafeERC20.sol";
import "./utils/SafeTokenConverter.sol";
import "./utils/Math.sol";


/// @title  Converter Ramp
/// @notice for conversion between different assets, use ITokenConverter
///         contract as abstract layer for convert different assets.
/// @dev All function calls are currently implemented without side effects
contract ConverterRamp is Ownable {
    using SafeTokenConverter for ITokenConverter;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice address to identify operations with ETH
    address public constant ETH_ADDRESS = address(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    event ReadedOracle(IRateOracle _oracle, uint256 _tokens, uint256 _equivalent);

    IDebtEngine immutable public debtEngine;
    ILoanManager immutable public loanManager;
    IERC20 immutable public debtEngineToken;

    constructor(ILoanManager _loanManager) public {
        loanManager = _loanManager;
        IERC20 _debtEngineToken = _loanManager.token();
        debtEngineToken = _debtEngineToken;
        IDebtEngine _debtEngine = _loanManager.debtEngine();
        debtEngine = _debtEngine;

        // Approve loanManager and debtEngine
        require(_debtEngineToken.safeApprove(address(_loanManager), uint(-1)), "constructor: fail LoanManager safeApprove");
        require(_debtEngineToken.safeApprove(address(_debtEngine), uint(-1)), "constructor: fail DebtEngine safeApprove");
    }

    function pay(
        ITokenConverter _converter,
        IERC20 _fromToken,
        uint256 _payAmount,
        uint256 _maxSpend,
        bytes32 _requestId,
        bytes calldata _oracleData
    ) external payable {
        uint256 amount;
        {
            // Get amount required, in RCN, for payment
            uint256 fee;
            (amount, fee) = getRequiredRcnPay(_requestId, _payAmount, _oracleData);

            // Pull funds from sender
            _pullConvertAndReturnExtra(
                _converter,
                _fromToken,
                amount + fee,
                _maxSpend
            );
        }

        // Execute the payment
        (, uint256 paidToken, uint256 paidFee) = debtEngine.payToken(_requestId, amount, msg.sender, _oracleData);

        // Convert any extra RCN and send it back it should not be reachable
        if (paidToken < amount) {
            uint256 buyBack = _converter.safeConvertFrom(
                _fromToken,
                debtEngineToken,
                amount - paidToken - paidFee,
                1
            );

            require(debtEngineToken.safeTransfer(msg.sender, buyBack), "error sending extra");
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
        // Get required RCN for lending the loan
        uint256 amount = getRequiredRcnLend(
            _cosigner,
            _requestId,
            _oracleData,
            _cosignerData
        );

        _pullConvertAndReturnExtra(
            _converter,
            _fromToken,
            amount,
            _maxSpend
        );

        loanManager.lend(
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
            _cosigner,
            _requestId,
            _oracleData,
            _cosignerData
        );

        return _converter.getPriceConvertTo(
            _fromToken,
            debtEngineToken,
            amountRcn
        );
    }

    /// @notice returns how much RCN is required for a given pay
    function getPayCostWithFee(
        ITokenConverter _converter,
        IERC20 _fromToken,
        bytes32 _requestId,
        uint256 _amount,
        bytes calldata _oracleData
    ) external returns (uint256) {
        (uint256 amount, uint256 fee) = getRequiredRcnPay(_requestId, _amount, _oracleData);

        return _converter.getPriceConvertTo(
            _fromToken,
            debtEngineToken,
            amount + fee
        );
    }

    /// @notice returns how much RCN is required for a given lend
    function getRequiredRcnLend(
        ICosigner _lenderCosignerAddress,
        bytes32 _requestId,
        bytes memory _oracleData,
        bytes memory _cosignerData
    ) internal returns (uint256) {
        // Load request amount
        uint256 amount = loanManager.getAmount(_requestId);

        // If loan has a cosigner, sum the cost
        if (_lenderCosignerAddress != ICosigner(0)) {
            amount = amount.add(
                _lenderCosignerAddress.cost(
                    loanManager,
                    _requestId,
                    _cosignerData,
                    _oracleData
                )
            );
        }

        // Convert amount in currency to amount in tokens
        IRateOracle oracle = loanManager.getOracle(_requestId);
        if (oracle == IRateOracle(0)) {
            return amount;
        }

        (uint256 tokens, uint256 equivalent) = oracle.readSample(_oracleData);

        emit ReadedOracle(oracle, tokens, equivalent);

        return tokens.mult(amount).divCeil(equivalent);
    }

    /// @notice returns how much RCN is required for a given pay
    function getRequiredRcnPay(
        bytes32 _requestId,
        uint256 _amount,
        bytes memory _oracleData
    ) internal returns (uint256 amount, uint256 fee) {
        (amount, fee) = loanManager.getClosingObligation(_requestId);

        // Load amount to pay
        if (_amount < amount) {
            amount = _amount;
            fee = debtEngine.toFee(_requestId, _amount);
        }

        // Convert amount and fee in currency to amount and fee in tokens
        IRateOracle oracle = loanManager.getOracle(_requestId);
        if (oracle == IRateOracle(0)) {
            return (amount, fee);
        }

        (uint256 tokens, uint256 equivalent) = oracle.readSample(_oracleData);

        emit ReadedOracle(oracle, tokens, equivalent);

        amount = tokens.mult(amount).divCeil(equivalent);
        fee = tokens.mult(fee).divCeil(equivalent);
    }

    function _pullConvertAndReturnExtra(
        ITokenConverter _converter,
        IERC20 _fromToken,
        uint256 _amount,
        uint256 _maxSpend
    ) private {
        // Pull limit amount from sender
        _pull(_fromToken, _maxSpend);

        uint256 spent = _converter.safeConvertTo(_fromToken, debtEngineToken, _amount, _maxSpend);

        if (spent < _maxSpend) {
            _transfer(_fromToken, msg.sender, _maxSpend - spent);
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
            require(_token.safeTransferFrom(msg.sender, address(this), _amount), "error pulling tokens");
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
            require(_token.safeTransfer(_to, _amount), "error sending tokens");
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
