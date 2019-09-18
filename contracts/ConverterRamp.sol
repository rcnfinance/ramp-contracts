pragma solidity 0.5.11;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./interfaces/Cosigner.sol";
import "./interfaces/diaspore/DebtEngine.sol";
import "./interfaces/diaspore/LoanManager.sol";
import "./interfaces/TokenConverter.sol";
import "./interfaces/RateOracle.sol";
import "./utils/SafeERC20.sol";
import "./utils/SafeTokenConverter.sol";
import "./utils/Math.sol";


/// @title  Converter Ramp
/// @notice for conversion between different assets, use TokenConverter
///         contract as abstract layer for convert different assets.
/// @dev All function calls are currently implemented without side effects
contract ConverterRamp is Ownable {
    using SafeTokenConverter for TokenConverter;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice address to identify operations with ETH
    address public constant ETH_ADDRESS = address(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    event Return(address _token, address _to, uint256 _amount);
    event ReadedOracle(address _oracle, uint256 _tokens, uint256 _equivalent);

    DebtEngine public debtEngine;
    LoanManager public loanManager;
    IERC20 public token;

    constructor(LoanManager _loanManager) public {
        loanManager = _loanManager;
        token = _loanManager.token();
        debtEngine = _loanManager.debtEngine();
    }

    function pay(
        TokenConverter _converter,
        IERC20 _fromToken,
        uint256 _payAmount,
        uint256 _maxSpend,
        bytes32 _requestId,
        bytes calldata _oracleData
    ) external payable {
        /// load RCN IERC20, we need it to pay
        DebtEngine _debtEngine = debtEngine;

        /// get amount required, in RCN, for payment
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

        // Pay the loan
        // the debtEngine is trusted
        // so we can approve it only once
        _approveOnlyOnce(_token, address(_debtEngine), amount);

        // execute the payment
        (, uint256 paidToken) = debtEngine.payToken(_requestId, amount, msg.sender, _oracleData);

        // Convert any extra RCN
        // and send it back
        // it should not be reachable
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
        TokenConverter _converter,
        IERC20 _fromToken,
        uint256 _maxSpend,
        address _cosigner,
        bytes32 _requestId,
        bytes memory _oracleData,
        bytes memory _cosignerData,
        bytes memory _callbackData
    ) public payable {
        /// load RCN IERC20
        LoanManager _loanManager = loanManager;

        /// get required RCN for lending the loan
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

        // approve token to loan manager only once
        // the loan manager is trusted
        _approveOnlyOnce(_token, address(_loanManager), amount);

        _loanManager.lend(
            _requestId,
            _oracleData,
            _cosigner,
            0,
            _cosignerData,
            _callbackData
        );

        // /// transfer loan to msg.sender
        debtEngine.transferFrom(address(this), msg.sender, uint256(_requestId));
    }

    function getLendCost(
        TokenConverter _converter,
        IERC20 _fromToken,
        address _cosigner,
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
        TokenConverter _converter,
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
        LoanManager _loanManager,
        address _lenderCosignerAddress,
        bytes32 _requestId,
        bytes memory _oracleData,
        bytes memory _cosignerData
    ) internal returns (uint256) {

        /// load loan manager and id
        uint256 amount = loanManager.getAmount(_requestId);

        /// load cosigner of loan
        Cosigner cosigner = Cosigner(_lenderCosignerAddress);

        /// if loan has a cosigner, sum the cost
        if (_lenderCosignerAddress != address(0)) {
            amount = amount.add(cosigner.cost(address(_loanManager), uint256(_requestId), _cosignerData, _oracleData));
        }

        /// load the  Oracle rate and convert required
        address oracle = loanManager.getOracle(uint256(_requestId));
        return getCurrencyToToken(oracle, amount, _oracleData);
    }

    /// @notice returns how much RCN is required for a given pay
    function getRequiredRcnPay(
        DebtEngine _debtEngine,
        bytes32 _requestId,
        uint256 _amount,
        bytes memory _oracleData
    ) internal returns (uint256 _result) {
        (,,Model model,, RateOracle oracle) = _debtEngine.debts(_requestId);

        // Load amount to pay
        uint256 amount = Math.min(
            model.getClosingObligation(_requestId),
            _amount
        );

        /// Read loan oracle
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

        (uint256 tokens, uint256 equivalent) = RateOracle(_oracle).readSample(_oracleData);

        emit ReadedOracle(_oracle, tokens, equivalent);
        return tokens.mul(_amount).divRound(equivalent);
    }


    function _convertAndReturn(
        TokenConverter _converter,
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

        require(_toToken.safeTransfer(msg.sender, buyBack), "error sending extra");
    }

    function _pullConvertAndReturnExtra(
        TokenConverter _converter,
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _amount,
        uint256 _maxSpend
    ) private {
        // Pull limit amount from sender
        _pull(_fromToken, _maxSpend);

        uint256 spent = _converter.safeConvertTo(_fromToken, _toToken, _amount, _maxSpend);

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

    function() external payable {}
}
