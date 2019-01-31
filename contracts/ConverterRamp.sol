pragma solidity 0.5.0;

import './interfaces/Cosigner.sol';
import './interfaces/diaspore/DebtEngine.sol';
import './interfaces/diaspore/LoanManager.sol';
import './interfaces/token/Token.sol';
import './interfaces/token/TokenConverter.sol';
import './interfaces/RateOracle.sol';
import './math/SafeMath.sol';
import './ownership/Ownable.sol';


contract ConverterRamp is Ownable {
    using SafeMath for uint256;

    address public constant ETH_ADDRESS = address(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
    uint256 public constant AUTO_MARGIN = 1000001;
    // index of convert rules for pay and lend
    uint256 public constant I_MARGIN_SPEND = 0;    // Extra sell percent of amount, 100.000 = 100%
    uint256 public constant I_MAX_SPEND = 1;       // Max spend on perform a sell, 0 = maximum
    uint256 public constant I_REBUY_THRESHOLD = 2; // Threshold of rebuy change, 0 if want to rebuy always
    // index of loan parameters for pay and lend
    uint256 public constant I_LOAN_MANAGER = 0;     // Loan Manager contract
    uint256 public constant I_REQUEST_ID = 1;      // Loan id on Diaspore
    // for pay
    uint256 public constant I_PAY_AMOUNT = 2; // Amount to pay of the loan
    uint256 public constant I_PAY_FROM = 3;   // The identity of the payer of loan
    // for lend
    uint256 public constant I_LEND_COSIGNER = 2; // Cosigner contract
    // address diaspore model
    uint256 public constant I_DEBT_ENGINE = 4; //

    event RequiredRebuy(address token, uint256 amount);
    event Return(address token, address to, uint256 amount);
    event OptimalSell(address token, uint256 amount);
    event RequiredRcn(uint256 required);
    event RunAutoMargin(uint256 loops, uint256 increment);

    function() external payable {
        require(msg.value > 0, 'The value is 0.');
    }

    function pay(
        TokenConverter converter,
        Token fromToken,
        bytes32[5] calldata loanParams,
        bytes calldata oracleData,
        uint256[3] calldata convertRules
    ) external payable returns (bool) {
        Token rcn = LoanManager(address(uint256(loanParams[I_LOAN_MANAGER]))).token();

        uint256 initialBalance = rcn.balanceOf(address(this));

        uint256 requiredRcn = getRequiredRcnPay(loanParams, oracleData);
        emit RequiredRcn(requiredRcn);

        uint256 optimalSell = getOptimalSell(converter, fromToken, rcn, requiredRcn, convertRules[I_MARGIN_SPEND]);
        emit OptimalSell(address(fromToken), optimalSell);

        pullAmount(fromToken, optimalSell);
        uint256 bought = convertSafe(converter, fromToken, rcn, optimalSell);

        // Pay loan

        DebtEngine debtEngine = DebtEngine(address(uint256(loanParams[I_DEBT_ENGINE])));
        require(rcn.approve(address(debtEngine), bought), "Error on payment approve");
        debtEngine.pay(loanParams[I_REQUEST_ID], bought, address(uint256(loanParams[I_PAY_FROM])), oracleData);
        require(rcn.approve(address(debtEngine), 0), "Error removing the payment approve");

        require(
            rebuyAndReturn({
                converter: converter,
                fromToken: rcn,
                toToken: fromToken,
                amount: rcn.balanceOf(address(this)) - initialBalance,
                spentAmount: optimalSell,
                convertRules: convertRules
            }),
            'Error rebuying the tokens'
        );

        require(rcn.balanceOf(address(this)) == initialBalance, 'Converter balance has incremented');
        return true;
    }

    function requiredLendSell(
        TokenConverter converter,
        Token fromToken,
        bytes32[4] calldata loanParams,
        bytes calldata oracleData,
        bytes calldata cosignerData,
        uint256[3] calldata convertRules
    ) external returns (uint256) {
        Token rcn = LoanManager(address(uint256(loanParams[I_LOAN_MANAGER]))).token();
        return getOptimalSell(
            converter,
            fromToken,
            rcn,
            getRequiredRcnLend(loanParams, oracleData, cosignerData),
            convertRules[I_MARGIN_SPEND]
        );
    }

    function requiredPaySell(
        TokenConverter converter,
        Token fromToken,
        bytes32[5] calldata loanParams,
        bytes calldata oracleData,
        uint256[3] calldata convertRules
    ) external returns (uint256) {
        Token rcn = LoanManager(address(uint256(loanParams[I_LOAN_MANAGER]))).token();
        return getOptimalSell(
            converter,
            fromToken,
            rcn,
            getRequiredRcnPay(loanParams, oracleData),
            convertRules[I_MARGIN_SPEND]
        );
    }

    function lend(
        TokenConverter converter,
        Token fromToken,
        bytes32[4] calldata loanParams,
        bytes calldata oracleData,
        bytes calldata cosignerData,
        uint256[3] calldata convertRules
    ) external payable returns (bool) {
        Token rcn = LoanManager(address(uint256(loanParams[I_LOAN_MANAGER]))).token();
        uint256 initialBalance = rcn.balanceOf(address(this));
        uint256 requiredRcn = getRequiredRcnLend(loanParams, oracleData, cosignerData);
        emit RequiredRcn(requiredRcn);

        uint256 optimalSell = getOptimalSell(converter, fromToken, rcn, requiredRcn, convertRules[I_MARGIN_SPEND]);
        emit OptimalSell(address(fromToken), optimalSell);

        pullAmount(fromToken, optimalSell);
        uint256 bought = convertSafe(converter, fromToken, rcn, optimalSell);

        // Lend loan
        require(rcn.approve(address(uint256(loanParams[I_LOAN_MANAGER])), bought), 'Error approving lend token transfer');
        require(executeLend(loanParams, oracleData, cosignerData), 'Error lending the loan');
        require(rcn.approve(address(uint256(loanParams[I_LOAN_MANAGER])), 0), 'Error removing approve');
        require(executeTransfer(loanParams, msg.sender), 'Error transfering the loan');

        require(
            rebuyAndReturn({
                converter: converter,
                fromToken: rcn,
                toToken: fromToken,
                amount: rcn.balanceOf(address(this)) - initialBalance,
                spentAmount: optimalSell,
                convertRules: convertRules
            }),
            'Error rebuying the tokens'
        );

        require(rcn.balanceOf(address(this)) == initialBalance, 'The contract balance should not change');

        return true;
    }

    function withdrawTokens(
        Token _token,
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        return _token.transfer(_to, _amount);
    }

    function withdrawEther(
        address payable _to,
        uint256 _amount
    ) external onlyOwner {
        _to.transfer(_amount);
    }

    function rebuyAndReturn(
        TokenConverter converter,
        Token fromToken,
        Token toToken,
        uint256 amount,
        uint256 spentAmount,
        uint256[3] memory convertRules
    ) internal returns (bool) {
        uint256 threshold = convertRules[I_REBUY_THRESHOLD];
        uint256 bought = 0;

        if (amount != 0) {
            if (amount > threshold) {
                bought = convertSafe(converter, fromToken, toToken, amount);
                emit RequiredRebuy(address(toToken), amount);
                emit Return(address(toToken), msg.sender, bought);
                transfer(toToken, msg.sender, bought);
            } else {
                emit Return(address(fromToken), msg.sender, amount);
                transfer(fromToken, msg.sender, amount);
            }
        }

        uint256 maxSpend = convertRules[I_MAX_SPEND];
        require(spentAmount.sub(bought) <= maxSpend || maxSpend == 0, 'Max spend exceeded');

        return true;
    }

    function getOptimalSell(
        TokenConverter converter,
        Token fromToken,
        Token toToken,
        uint256 requiredTo,
        uint256 extraSell
    ) internal returns (uint256 sellAmount) {
        uint256 sellRate = (10 ** 18 * converter.getReturn(toToken, fromToken, requiredTo)) / requiredTo;
        if (extraSell == AUTO_MARGIN) {
            uint256 expectedReturn = 0;
            uint256 optimalSell = applyRate(requiredTo, sellRate);
            uint256 increment = applyRate(requiredTo / 100000, sellRate);
            uint256 returnRebuy;
            uint256 cl;

            while (expectedReturn < requiredTo && cl < 10) {
                optimalSell += increment;
                returnRebuy = converter.getReturn(fromToken, toToken, optimalSell);
                optimalSell = (optimalSell * requiredTo) / returnRebuy;
                expectedReturn = returnRebuy;
                cl++;
            }
            emit RunAutoMargin(cl, increment);

            return optimalSell;
        } else {
            return applyRate(requiredTo, sellRate).mul(uint256(100000).add(extraSell)) / 100000;
        }
    }

    function convertSafe(
        TokenConverter converter,
        Token fromToken,
        Token toToken,
        uint256 amount
    ) internal returns (uint256 bought) {
        if (address(fromToken) != ETH_ADDRESS) require(fromToken.approve(address(converter), amount), 'Error approving token transfer');
        uint256 prevBalance = address(toToken) != ETH_ADDRESS ? toToken.balanceOf(address(this)) : address(this).balance;
        uint256 sendEth = address(fromToken) == ETH_ADDRESS ? amount : 0;
        uint256 boughtAmount = converter.convert.value(sendEth)(fromToken, toToken, amount, 1);
        require(
            boughtAmount == (address(toToken) != ETH_ADDRESS ? toToken.balanceOf(address(this)) : address(this).balance) - prevBalance,
            'Bought amound does does not match'
        );
        if (address(fromToken) != ETH_ADDRESS) require(fromToken.approve(address(converter), 0), 'Error removing token approve');
        return boughtAmount;
    }

    function executeLend(
        bytes32[4] memory params,
        bytes memory oracleData,
        bytes memory cosignerData
    ) internal returns (bool) {
        LoanManager loanManager = LoanManager(address(uint256(params[I_LOAN_MANAGER])));
        bytes32 id = params[I_REQUEST_ID];
        return loanManager.lend(id, oracleData, address(uint256(params[I_LEND_COSIGNER])), 0, cosignerData);
    }

    function executeTransfer(
        bytes32[4] memory params,
        address to
    ) internal returns (bool) {
        DebtEngine debtEngine = DebtEngine(address(uint256(params[I_DEBT_ENGINE])));
        debtEngine.transferFrom(address(this), to, uint256(params[I_REQUEST_ID]));
        return true;
    }

    function applyRate(
        uint256 amount,
        uint256 rate
    ) internal pure returns (uint256) {
        return amount.mul(rate) / 10 ** 18;
    }

    function getRequiredRcnLend(
        bytes32[4] memory params,
        bytes memory oracleData,
        bytes memory cosignerData
    ) internal returns (uint256 required) {
        LoanManager loanManager = LoanManager(address(uint256(params[I_LOAN_MANAGER])));
        uint256 id = uint256(params[I_REQUEST_ID]);
        Cosigner cosigner = Cosigner(address(uint256(params[I_LEND_COSIGNER])));

        if (address(cosigner) != address(0)) {
            required += cosigner.cost(address(loanManager), id, cosignerData, oracleData);
        }

        RateOracle rateOracle = RateOracle(loanManager.getOracle(id));
        (uint256 _tokens, uint256 _equivalent) = rateOracle.readSample(oracleData);
        required += _toToken(uint256(params[I_PAY_AMOUNT]), _tokens, _equivalent);
    }

    function getRequiredRcnPay(
        bytes32[5] memory params,
        bytes memory oracleData
    ) internal returns (uint256 _result) {
        LoanManager loanManager = LoanManager(address(uint256(params[I_LOAN_MANAGER])));
        uint256 id = uint256(params[I_REQUEST_ID]);

        RateOracle rateOracle = RateOracle(loanManager.getOracle(id));
        (uint256 _tokens, uint256 _equivalent) = rateOracle.readSample(oracleData);

        return _toToken(uint256(params[I_PAY_AMOUNT]), _tokens, _equivalent);
    }

    function _toToken(
        uint256 _amount,
        uint256 _tokens,
        uint256 _equivalent
    ) internal pure returns (uint256 _result) {
        require(_tokens != 0, 'Oracle provided invalid rate');
        uint256 aux = _tokens.mul(_amount);
        _result = aux / _equivalent;
        if (aux % _equivalent > 0) {
            _result = _result.add(1);
        }
    }

    function pullAmount(
        Token token,
        uint256 amount
    ) private {
        if (address(token) == ETH_ADDRESS) {
            require(msg.value >= amount, 'Error pulling ETH amount');
            if (msg.value > amount) {
                msg.sender.transfer(msg.value - amount);
            }
        } else {
            require(token.transferFrom(msg.sender, address(this), amount), 'Error pulling Token amount');
        }
    }

    function transfer(
        Token _token,
        address payable _to,
        uint256 _amount
    ) private {
        if (address(_token) == ETH_ADDRESS) {
            _to.transfer(_amount);
        } else {
            require(_token.transfer(_to, _amount), 'Error sending tokens');
        }
    }

}
