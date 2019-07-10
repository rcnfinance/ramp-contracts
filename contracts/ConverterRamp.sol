pragma solidity 0.5.10;

import './interfaces/Cosigner.sol';
import './interfaces/diaspore/DebtEngine.sol';
import './interfaces/diaspore/LoanManager.sol';
import './interfaces/token/Token.sol';
import './interfaces/token/TokenConverter.sol';
import './interfaces/RateOracle.sol';
import 'openzeppelin-solidity/contracts/math/SafeMath.sol';
import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';


contract ConverterRamp is Ownable {
    using SafeMath for uint256;

    address public constant ETH_ADDRESS = address(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
    uint256 public constant AUTO_MARGIN = 1000001;
    // index of convert rules for pay and lend
    uint256 public constant I_MARGIN_SPEND = 0;     // Extra sell percent of amount, 100.000 = 100%
    uint256 public constant I_MAX_SPEND = 1;        // Max spend on perform a sell, 0 = maximum
    uint256 public constant I_REBUY_THRESHOLD = 2;  // Threshold of rebuy change, 0 if want to rebuy always
    // index of loan parameters for pay and lend
    uint256 public constant I_LOAN_MANAGER = 0;     // Loan Manager contract
    uint256 public constant I_REQUEST_ID = 1;       // Loan id on Diaspore
    // for pay
    uint256 public constant I_PAY_AMOUNT = 2;       // Amount to pay of the loan
    uint256 public constant I_PAY_FROM = 3;         // The identity of the payer of loan
    // for lend
    uint256 public constant I_LEND_COSIGNER = 2;    // Cosigner contract
    uint256 public constant I_DEBT_ENGINE = 4;      // Address of debt engine

    event RequiredRebuy(address token, uint256 amount);
    event Return(address token, address to, uint256 amount);
    event OptimalSell(address token, uint256 amount);
    event RequiredRcn(uint256 required);
    event RunAutoMargin(uint256 loops, uint256 increment);

    function() external payable {
        require(msg.value > 0, 'The value is 0.');
    }

    /*
        Pays a loan using fromTokens
    */
    function pay(
        TokenConverter converter,
        Token fromToken,
        bytes32[5] calldata loanParams,
        bytes calldata oracleData,
        uint256[3] calldata convertRules
    ) external payable returns (bool) {
        // Load RCN Token, we need it to pay
        Token rcn = LoanManager(address(uint256(loanParams[I_LOAN_MANAGER]))).token();

        // Load initial RCN balance of contract (probably 0)
        uint256 initialBalance = rcn.balanceOf(address(this));

        // Get amount required, in RCN, for payment
        uint256 requiredRcn = getRequiredRcnPay(loanParams, oracleData);
        emit RequiredRcn(requiredRcn);

        // TODO: Remove
        // Load how much to sell to obtain requiredRcn
        uint256 optimalSell = getOptimalSell(converter, fromToken, rcn, requiredRcn, convertRules[I_MARGIN_SPEND]);
        emit OptimalSell(address(fromToken), optimalSell);

        // Pull amount
        pullAmount(fromToken, optimalSell);

        // Convert using token converter
        uint256 bought = convertSafe(converter, fromToken, rcn, optimalSell);

        // Pay loan
        DebtEngine debtEngine = DebtEngine(address(uint256(loanParams[I_DEBT_ENGINE])));
        require(rcn.approve(address(debtEngine), bought), "Error on payment approve");
        debtEngine.pay(loanParams[I_REQUEST_ID], bought, address(uint256(loanParams[I_PAY_FROM])), oracleData);
        require(rcn.approve(address(debtEngine), 0), "Error removing the payment approve");

        // Convert any exceding RCN into fromToken
        // and send token back to msg.sender
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

        // The contract balance should remain the same
        require(rcn.balanceOf(address(this)) == initialBalance, 'Converter balance has incremented');

        return true;
    }

    /*
        Returns the required sell for lending a given loan

        @dev For external usage (as view)
    */
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

    /*
        Returns the required sell for paying a given loan

        @dev For external usage (as view)
    */
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

    /*
        Lends a loan using fromTokens, transfer loan ownership to msg.sender
    */
    function lend(
        TokenConverter converter,
        Token fromToken,
        bytes32[4] calldata loanParams,
        bytes calldata oracleData,
        bytes calldata cosignerData,
        uint256[3] calldata convertRules
    ) external payable returns (bool) {
        // Load RCN Token
        Token rcn = LoanManager(address(uint256(loanParams[I_LOAN_MANAGER]))).token();

        // Load balance prior operation
        uint256 initialBalance = rcn.balanceOf(address(this));

        // Get required RCN for lending the loan
        uint256 requiredRcn = getRequiredRcnLend(loanParams, oracleData, cosignerData);
        emit RequiredRcn(requiredRcn);

        // Load optimal fromToken sell to obtain requiredRcn
        uint256 optimalSell = getOptimalSell(converter, fromToken, rcn, requiredRcn, convertRules[I_MARGIN_SPEND]);
        emit OptimalSell(address(fromToken), optimalSell);

        // Pull required fromToken amount to sell
        pullAmount(fromToken, optimalSell);

        // Convert fromToken into RCN
        uint256 bought = convertSafe(converter, fromToken, rcn, optimalSell);

        // Lend loan
        require(rcn.approve(address(uint256(loanParams[I_LOAN_MANAGER])), bought), 'Error approving lend token transfer');
        require(executeLend(loanParams, oracleData, cosignerData), 'Error lending the loan');
        require(rcn.approve(address(uint256(loanParams[I_LOAN_MANAGER])), 0), 'Error removing approve');
        // Transfer loan to msg.sender
        require(executeTransfer(loanParams, msg.sender), 'Error transfering the loan');

        // Convert any exceding RCN into fromToken
        // and send token back to msg.sender
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

        // The contract balance should remain the same
        require(rcn.balanceOf(address(this)) == initialBalance, 'The contract balance should not change');

        return true;
    }

    /*
        Withdraw tokens stalled in the contract
    */
    function withdrawTokens(
        Token _token,
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        return _token.transfer(_to, _amount);
    }

    /*
        Withdraw ether stalled in the contract
    */
    function withdrawEther(
        address payable _to,
        uint256 _amount
    ) external onlyOwner {
        _to.transfer(_amount);
    }

    /*
        Rebuys and/or returns an amount to the msg.sender, acording to the rules set by convertRules

        Validates that spentAmount is lower than the maxSend
    */
    function rebuyAndReturn(
        TokenConverter converter,
        Token fromToken,
        Token toToken,
        uint256 amount,
        uint256 spentAmount,
        uint256[3] memory convertRules
    ) internal returns (bool) {
        // Load required amount to convert back to toToken
        // (avoid irrelevant convertions, save gas)
        uint256 threshold = convertRules[I_REBUY_THRESHOLD];

        // Store bought amount
        // if nothing is bought, zero
        uint256 bought = 0;

        if (amount != 0) {
            if (amount > threshold) {
                // Amount exceeds threshold, must convert to toToken
                bought = convertSafe(converter, fromToken, toToken, amount);
                emit RequiredRebuy(address(toToken), amount);
                emit Return(address(toToken), msg.sender, bought);
                // Transfer bought tokens to msg.sender
                transfer(toToken, msg.sender, bought);
            } else {
                // Amount does not amerite convertion
                // send as fromToken
                emit Return(address(fromToken), msg.sender, amount);
                transfer(fromToken, msg.sender, amount);
            }
        }

        // The spentAmount accounting the re-bought
        // should be lower than the max spend parameter
        uint256 maxSpend = convertRules[I_MAX_SPEND];
        require(spentAmount.sub(bought) <= maxSpend || maxSpend == 0, 'Max spend exceeded');

        return true;
    }

    /*
        TODO: Remove this method, replace it with a new method in TokenConverter

        Returns the optimal amount to sell in order to buy requiredTo toToken
    */
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

    /*
        Converts an amount using a converter, not trusting the converter,
        validates all convertions using the token contract.

        Handles, internally, ETH convertions
    */
    function convertSafe(
        TokenConverter converter,
        Token fromToken,
        Token toToken,
        uint256 amount
    ) internal returns (uint256 bought) {
        // If we are converting from ETH, we don't need to approve the converter
        if (address(fromToken) != ETH_ADDRESS) {
            require(fromToken.approve(address(converter), amount), 'Error approving token transfer');
        }

        // Store the previus balance to validate after convertion
        uint256 prevBalance = address(toToken) != ETH_ADDRESS ? toToken.balanceOf(address(this)) : address(this).balance;

        // Call convert in token converter
        uint256 sendEth = address(fromToken) == ETH_ADDRESS ? amount : 0;
        uint256 boughtAmount = converter.convert.value(sendEth)(fromToken, toToken, amount, 1);

        // toToken balance should have increased by boughtAmount
        require(
            boughtAmount == (address(toToken) != ETH_ADDRESS ? toToken.balanceOf(address(this)) : address(this).balance) - prevBalance,
            'Bought amound does does not match'
        );

        // If we are converting from a token, remove the approve
        if (address(fromToken) != ETH_ADDRESS) require(fromToken.approve(address(converter), 0), 'Error removing token approve');

        // Return the bought amount
        return boughtAmount;
    }

    /*
        Execute lend, reading from params
    */
    function executeLend(
        bytes32[4] memory params,
        bytes memory oracleData,
        bytes memory cosignerData
    ) internal returns (bool) {
        LoanManager loanManager = LoanManager(address(uint256(params[I_LOAN_MANAGER])));
        bytes32 id = params[I_REQUEST_ID];
        return loanManager.lend(id, oracleData, address(uint256(params[I_LEND_COSIGNER])), 0, cosignerData);
    }

    /*
        Execute transfer debt, reading from params
    */
    function executeTransfer(
        bytes32[4] memory params,
        address to
    ) internal returns (bool) {
        DebtEngine debtEngine = DebtEngine(address(uint256(params[I_DEBT_ENGINE])));
        debtEngine.transferFrom(address(this), to, uint256(params[I_REQUEST_ID]));
        return true;
    }

    /*
        TODO: Remove with getOptimalSell

        Aplies a rate using a previus convertion
    */
    function applyRate(
        uint256 amount,
        uint256 rate
    ) internal pure returns (uint256) {
        return amount.mul(rate) / 10 ** 18;
    }

    /*
        Returns how much RCN is required for a given lend
    */
    function getRequiredRcnLend(
        bytes32[4] memory params,
        bytes memory oracleData,
        bytes memory cosignerData
    ) internal returns (uint256 required) {
        // Load loan manager and id
        LoanManager loanManager = LoanManager(address(uint256(params[I_LOAN_MANAGER])));
        uint256 id = uint256(params[I_REQUEST_ID]);

        // Load cosigner of loan
        Cosigner cosigner = Cosigner(address(uint256(params[I_LEND_COSIGNER])));

        // If loan has a cosigner, sum the cost
        if (address(cosigner) != address(0)) {
            required += cosigner.cost(address(loanManager), id, cosignerData, oracleData);
        }

        // Load the  Oracle rate and convert required
        // FIXME Loan with no oracle
        RateOracle rateOracle = RateOracle(loanManager.getOracle(id));
        (uint256 _tokens, uint256 _equivalent) = rateOracle.readSample(oracleData);
        // FIXME return tokenAmount, do not add amounts
        required += _toToken(uint256(params[I_PAY_AMOUNT]), _tokens, _equivalent);
    }

    /*
        Returns how much RCN is required for a given pay
    */
    function getRequiredRcnPay(
        bytes32[5] memory params,
        bytes memory oracleData
    ) internal returns (uint256 _result) {
        // Load LoanManager and ID
        LoanManager loanManager = LoanManager(address(uint256(params[I_LOAN_MANAGER])));
        uint256 id = uint256(params[I_REQUEST_ID]);

        // Read loan oracle
        // FIXME Loan with no oracle
        RateOracle rateOracle = RateOracle(loanManager.getOracle(id));
        (uint256 _tokens, uint256 _equivalent) = rateOracle.readSample(oracleData);

        // Convert the amount to RCN using the Oracle rate
        return _toToken(uint256(params[I_PAY_AMOUNT]), _tokens, _equivalent);
    }

    /*
        Copy of DebtEngine _toToken
        converts a given amount to RCN tokens, using the Oracle sample
    */
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

    /*
        Pulls an amount in token or eth from the msg.sender

        @dev If ETH, returns the excedent
    */
    function pullAmount(
        Token token,
        uint256 amount
    ) private {
        // Handle both ETH and tokens
        if (address(token) == ETH_ADDRESS) {
            // If ETH, require msg.value to be at least the required amount
            require(msg.value >= amount, 'Error pulling ETH amount');
            // Return any exceding ETH, if any
            if (msg.value > amount) {
                msg.sender.transfer(msg.value - amount);
            }
        } else {
            // If tokens, only perform a transferFrom
            require(token.transferFrom(msg.sender, address(this), amount), 'Error pulling Token amount');
        }
    }

    /*
        Transfers token or ETH
    */
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
