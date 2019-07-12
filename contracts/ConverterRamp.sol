pragma solidity 0.5.10;

import './interfaces/Cosigner.sol';
import './interfaces/diaspore/DebtEngine.sol';
import './interfaces/diaspore/LoanManager.sol';
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import './interfaces/token/TokenConverter.sol';
import './interfaces/RateOracle.sol';
import 'openzeppelin-solidity/contracts/math/SafeMath.sol';
import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';


contract ConverterRamp is Ownable {
    using SafeMath for uint256;

    address public constant ETH_ADDRESS = address(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
    uint256 public constant AUTO_MARGIN = 1000001;
    // index of loan parameters for pay and lend
    uint256 public constant I_LOAN_MANAGER = 0;     // Loan Manager contract
    uint256 public constant I_REQUEST_ID = 1;       // Loan id on Diaspore
    // for pay
    uint256 public constant I_PAY_AMOUNT = 2;       // Amount to pay of the loan
    uint256 public constant I_PAY_FROM = 3;         // The identity of the payer of loan
    // for lend
    uint256 public constant I_LEND_COSIGNER = 2;    // Cosigner contract
    uint256 public constant I_DEBT_ENGINE = 4;      // Address of debt engine

    event Return(address token, address to, uint256 amount);
    event RequiredRcn(uint256 required);

    function() external payable {
        require(msg.value > 0, 'The value is 0.');
    }

    /*
    Pays a loan using fromTokens
    */
    function pay(
        TokenConverter converter,
        IERC20 fromToken,
        bytes32[5] calldata loanParams,
        bytes calldata oracleData
    ) external payable returns (bool) {
        // Load RCN IERC20, we need it to pay
        IERC20 token = LoanManager(address(uint256(loanParams[I_LOAN_MANAGER]))).token();

        // Load initial RCN balance of contract (probably 0)
        uint256 initialBalance = token.balanceOf(address(this));

        // Get amount required, in RCN, for payment
        uint256 amount = getRequiredRcnPay(loanParams, oracleData);
        emit RequiredRcn(amount);

        // Pull amount
        pullAmount(fromToken, amount);

        // Convert using token converter
        convertSafe(converter, fromToken, token, amount);

        // Pay loan
        DebtEngine debtEngine = DebtEngine(address(uint256(loanParams[I_DEBT_ENGINE])));
        require(token.approve(address(debtEngine), amount), "Error on payment approve");
        debtEngine.pay(loanParams[I_REQUEST_ID], amount, address(uint256(loanParams[I_PAY_FROM])), oracleData);
        require(token.approve(address(debtEngine), 0), "Error removing the payment approve");

        // The contract balance should remain the same
        require(token.balanceOf(address(this)) == initialBalance, 'Converter balance has incremented');

        return true;
    }

    /*
        Lends a loan using fromTokens, transfer loan ownership to msg.sender
    */
    function lend(
        TokenConverter converter,
        IERC20 fromToken,
        bytes32[4] calldata loanParams,
        bytes calldata oracleData,
        bytes calldata cosignerData
    ) external payable returns (bool) {
        // Load RCN IERC20
        IERC20 token = LoanManager(address(uint256(loanParams[I_LOAN_MANAGER]))).token();

        // Load balance prior operation
        uint256 initialBalance = token.balanceOf(address(this));

        // Get required RCN for lending the loan
        uint256 amount = getRequiredRcnLend(loanParams, oracleData, cosignerData);
        emit RequiredRcn(amount);

        // Pull required fromToken amount to sell
        pullAmount(fromToken, amount);

        // Convert fromToken into RCN
        convertSafe(converter, fromToken, token, amount);

        // Lend loan
        require(token.approve(address(uint256(loanParams[I_LOAN_MANAGER])), amount), 'Error approving lend token transfer');
        require(executeLend(loanParams, oracleData, cosignerData), 'Error lending the loan');
        require(token.approve(address(uint256(loanParams[I_LOAN_MANAGER])), 0), 'Error removing approve');
        
        // Transfer loan to msg.sender
        require(executeTransfer(loanParams, msg.sender), 'Error transfering the loan');

        // The contract balance should remain the same
        require(token.balanceOf(address(this)) == initialBalance, 'The contract balance should not change');

        return true;
    }

    /*
        Withdraw tokens stalled in the contract
    */
    function withdrawTokens(
        IERC20 _token,
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
        Converts an amount using a converter, not trusting the converter,
        validates all convertions using the token contract.

        Handles, internally, ETH convertions
    */
    function convertSafe(
        TokenConverter _converter,
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _amount
    ) internal returns (uint256 bought) {
        // If we are converting from ETH, we don't need to approve the converter
        if (address(_fromToken) != ETH_ADDRESS) {
            require(_fromToken.approve(address(_converter), _amount), 'Error approving token transfer');
        }

        // Store the previus balance to validate after convertion
        uint256 prevBalance = address(_toToken) != ETH_ADDRESS ? _toToken.balanceOf(address(this)) : address(this).balance;

        // Call convert in token converter
        uint256 sendEth = address(_fromToken) == ETH_ADDRESS ? _amount : 0;
        _converter.convert.value(sendEth)(_fromToken, _toToken, _amount);

        // _toToken balance should have increased by _amount
        require(
            _amount == (address(_toToken) != ETH_ADDRESS ? _toToken.balanceOf(address(this)) : address(this).balance) - prevBalance,
            'Bought amound does does not match'
        );

        // If we are converting from a token, remove the approve
        if (address(_fromToken) != ETH_ADDRESS) require(_fromToken.approve(address(_converter), 0), 'Error removing token approve');

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
        Pulls an _amount in _token or eth from the msg.sender
        @dev If ETH, returns the excedent
    */
    function pullAmount(
        IERC20 _token,
        uint256 _amount
    ) private {
        // Handle both ETH and tokens
        if (address(_token) == ETH_ADDRESS) {
            // If ETH, require msg.value to be at least the required _amount
            require(msg.value >= _amount, 'Error pulling ETH _amount');
            // Return any exceding ETH, if any
            if (msg.value > _amount) {
                msg.sender.transfer(msg.value - _amount);
            }
        } else {
            // If tokens, only perform a transferFrom
            require(_token.transferFrom(msg.sender, address(this), _amount), 'Error pulling token amount');
        }
    }

    /*
        Transfers token or ETH
    */
    function transfer(
        IERC20 _token,
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
