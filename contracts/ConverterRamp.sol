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

    event Return(address token, address to, uint256 amount);
    event RequiredRcn(uint256 required);

    function() external payable {
        require(msg.value > 0, 'The value is 0.');
    }

    /*
    Pays a loan using fromTokens
    */
    function pay(
        address _converter,
        address _fromToken,
        address _loanManagerAddress,
        address _debtEngineAddress,
        address _payFrom,
        bytes32 _requestId,
        uint256 _amountToPay,
        bytes calldata oracleData
    ) external payable returns (bool) {
        // Load RCN IERC20, we need it to pay
        IERC20 token = LoanManager(_loanManagerAddress).token();

        // Load initial RCN balance of contract (probably 0)
        uint256 initialBalance = token.balanceOf(address(this));

        // Get amount required, in RCN, for payment
        uint256 amount = getRequiredRcnPay(_loanManagerAddress, _requestId, _amountToPay, oracleData);
        emit RequiredRcn(amount);

        // Pull amount
        pullAmount(_fromToken, amount);

        // Convert using token _converter
        convertSafe(_converter, _fromToken, address(token), amount);

        // Pay loan
        DebtEngine debtEngine = DebtEngine(_debtEngineAddress);
        require(token.approve(_debtEngineAddress, amount), "Error on payment approve");
        debtEngine.pay(_requestId, amount, _payFrom, oracleData);
        require(token.approve(_debtEngineAddress, 0), "Error removing the payment approve");

        // The contract balance should remain the same
        require(token.balanceOf(address(this)) == initialBalance, 'Converter balance has incremented');

        return true;
    }

    /*
        Lends a loan using fromTokens, transfer loan ownership to msg.sender
    */
    function lend(
        address _converter,
        address _fromToken,
        address loanManagerAddress,
        address lenderCosignerAddress,
        address debtEngineAddress,
        bytes32 requestId,
        uint256 amountToPay,
        bytes memory oracleData,
        bytes memory cosignerData
    ) public payable returns (bool) {
        // Load RCN IERC20
        LoanManager loanManager = LoanManager(loanManagerAddress);
        IERC20 token = loanManager.token();

        // Load balance prior operation
        uint256 initialBalance = token.balanceOf(address(this));

        // Get required RCN for lending the loan
        uint256 amount = getRequiredRcnLend(
            loanManagerAddress, 
            lenderCosignerAddress, 
            requestId, 
            amountToPay, 
            oracleData, 
            cosignerData
        );
        emit RequiredRcn(amount);

        // Pull required _fromToken amount to sell
        pullAmount(_fromToken, amount);

        // Convert _fromToken into RCN
        convertSafe(_converter, _fromToken, address(token), amount);

        // Lend loan
        require(token.approve(loanManagerAddress, amount), 'Error approving lend token transfer');
        loanManager.lend(requestId, oracleData, lenderCosignerAddress, 0, cosignerData);
        require(token.approve(loanManagerAddress, 0), 'Error removing approve');
        
        // Transfer loan to msg.sender
        DebtEngine debtEngine = DebtEngine(debtEngineAddress);
        debtEngine.transferFrom(address(this), msg.sender, uint256(requestId));

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
        address _converter,
        address _fromTokenAddress,
        address _toTokenAddress,
        uint256 _amount
    ) internal returns (uint256 bought) {

        IERC20 fromToken = IERC20(_fromTokenAddress);
        IERC20 toToken = IERC20(_toTokenAddress);
        TokenConverter tokenConverter = TokenConverter(_converter);

        // If we are converting from ETH, we don't need to approve the converter
        if (_toTokenAddress != ETH_ADDRESS) {
            require(fromToken.approve(address(tokenConverter), _amount), 'Error approving token transfer');
        }

        // Store the previus balance to validate after convertion
        uint256 prevBalance = _toTokenAddress != ETH_ADDRESS ? toToken.balanceOf(address(this)) : address(this).balance;

        // Call convert in token converter
        uint256 sendEth = _fromTokenAddress == ETH_ADDRESS ? _amount : 0;
        tokenConverter.convert.value(sendEth)(fromToken, toToken, _amount);

        // toToken balance should have increased by _amount
        require(
            _amount == (_toTokenAddress != ETH_ADDRESS ? toToken.balanceOf(address(this)) : address(this).balance) - prevBalance,
            'Bought amound does does not match'
        );

        // If we are converting from a token, remove the approve
        if (_fromTokenAddress != ETH_ADDRESS) require(fromToken.approve(address(tokenConverter), 0), 'Error removing token approve');

    }

    /*
        Returns how much RCN is required for a given lend
    */
    function getRequiredRcnLend(
        address _loanManagerAddress,
        address _lenderCosignerAddress,
        bytes32 _requestId,
        uint256 _amountToPay,
        bytes memory _oracleData,
        bytes memory _cosignerData
    ) internal returns (uint256 required) {
        // Load loan manager and id
        LoanManager loanManager = LoanManager(_loanManagerAddress);

        // Load cosigner of loan
        Cosigner cosigner = Cosigner(_lenderCosignerAddress);

        // If loan has a cosigner, sum the cost
        if (_lenderCosignerAddress != address(0)) {
            required = required.add(cosigner.cost(_loanManagerAddress, uint256(_requestId), _cosignerData, _oracleData));
        }

        // Load the  Oracle rate and convert required
        // FIXME Loan with no oracle
        RateOracle rateOracle = RateOracle(loanManager.getOracle(uint256(_requestId)));
        (uint256 _tokens, uint256 _equivalent) = rateOracle.readSample(_oracleData);
        // FIXME return tokenAmount, do not add amounts
        required = required.add(_toToken(_amountToPay, _tokens, _equivalent));
    }

    /*
        Returns how much RCN is required for a given pay
    */
    function getRequiredRcnPay(
        address _loanManagerAddress,
        bytes32 _requestId,
        uint256 _amountToPay,
        bytes memory _oracleData
    ) internal returns (uint256 _result) {
        // Load LoanManager and ID
        LoanManager loanManager = LoanManager(_loanManagerAddress);

        // Read loan oracle
        // FIXME Loan with no oracle
        RateOracle rateOracle = RateOracle(loanManager.getOracle(uint256(_requestId)));
        (uint256 _tokens, uint256 _equivalent) = rateOracle.readSample(_oracleData);

        // Convert the amount to RCN using the Oracle rate
        return _toToken(_amountToPay, _tokens, _equivalent);
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
        address _token,
        uint256 _amount
    ) private {
        // Handle both ETH and tokens
        if (_token == ETH_ADDRESS) {
            // If ETH, require msg.value to be at least the required _amount
            require(msg.value >= _amount, 'Error pulling ETH _amount');
            // Return any exceding ETH, if any
            if (msg.value > _amount) {
                msg.sender.transfer(msg.value - _amount);
            }
        } else {
            // If tokens, only perform a transferFrom
            require(IERC20(_token).transferFrom(msg.sender, address(this), _amount), 'Error pulling token amount');
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
