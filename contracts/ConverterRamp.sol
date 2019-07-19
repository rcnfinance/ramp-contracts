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
    event OptimalSell(address token, uint256 amount);

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

        // Get amount required, in RCN, for payment
        uint256 amount = getRequiredRcnPay(_loanManagerAddress, _requestId, _amountToPay, oracleData);
        (uint256 tokenCost, uint256 etherCost) = getCost(amount, _converter, _fromToken, address(token));

        // Pull amount
        pullAmount(_fromToken, tokenCost, etherCost);

        // Convert using token _converter
        convertSafe(_converter, _fromToken, address(token), amount, tokenCost, etherCost);

        // Pay loan
        DebtEngine debtEngine = DebtEngine(_debtEngineAddress);
        require(token.approve(_debtEngineAddress, amount), "Error on payment approve");
        debtEngine.pay(_requestId, amount, _payFrom, oracleData);
        require(token.approve(_debtEngineAddress, 0), "Error removing the payment approve");

        return true;
    }

    /*
        Lends a loan using fromTokens, transfer loan ownership to msg.sender
    */
    function lend(
        address _converter,
        address _fromToken,
        address _loanManagerAddress,
        address _lenderCosignerAddress,
        address _debtEngineAddress,
        bytes32 _requestId,
        uint256 _amountToLend,
        bytes memory _oracleData,
        bytes memory _cosignerData,
        bytes memory _callbackData
    ) public payable {
        // Load RCN IERC20
        IERC20 token = LoanManager(_loanManagerAddress).token();

        // Get required RCN for lending the loan
        uint256 amount = getRequiredRcnLend(
            _loanManagerAddress, 
            _lenderCosignerAddress, 
            _requestId, 
            _amountToLend, 
            _oracleData, 
            _cosignerData
        );

        // Pull required _fromToken amount to sell
        (uint256 tokenCost, uint256 etherCost) = getCost(amount, _converter, _fromToken, address(token));
        pullAmount(_fromToken, tokenCost, etherCost);

        // Convert _fromToken into RCN
        convertSafe(_converter, _fromToken, address(token), amount, tokenCost, etherCost);

        // Lend loan
        require(token.approve(_loanManagerAddress, amount), 'Error approving lend token transfer');
        LoanManager(_loanManagerAddress).lend(
            _requestId, 
            _oracleData, 
            _lenderCosignerAddress, 
            0, 
            _cosignerData, 
            _callbackData
        );
        require(token.approve(_loanManagerAddress, 0), 'Error removing approve');
        
        // Transfer loan to msg.sender
        DebtEngine(_debtEngineAddress).transferFrom(address(this), msg.sender, uint256(_requestId));

        // The contract balance should remain the same
        require(token.balanceOf(address(this)) == 0, 'The contract balance should not change');

    }

    function getCost(uint _amount, address _converter, address _fromToken, address _token) internal returns (uint256, uint256)  {
        TokenConverter tokenConverter = TokenConverter(_converter);
        if (_fromToken != ETH_ADDRESS) {
            return tokenConverter.getPrice(_fromToken, _token, _amount);
        } else {
            return tokenConverter.getPrice(_token, _amount);
        }
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
        uint256 _amount,
        uint256 _tokenCost,
        uint256 _etherCost
    ) internal returns (uint256 bought) {

        IERC20 fromToken = IERC20(_fromTokenAddress);
        IERC20 toToken = IERC20(_toTokenAddress);
        TokenConverter tokenConverter = TokenConverter(_converter);

        // If we are converting from ETH, we don't need to approve the converter
        if (_toTokenAddress != ETH_ADDRESS) {
            require(fromToken.approve(address(tokenConverter), _tokenCost), 'Error approving token transfer');
        }

        // Store the previus balance to validate after convertion
        uint256 prevBalance = _toTokenAddress != ETH_ADDRESS ? toToken.balanceOf(address(this)) : address(this).balance;

        // Call convert in token converter
        uint256 sendEth = _fromTokenAddress == ETH_ADDRESS ? _amount : 0;
        tokenConverter.convert.value(sendEth)(fromToken, toToken, _amount, _tokenCost, _etherCost, msg.sender);

        // toToken balance should have increased by _amount
        require(
            _amount == (_toTokenAddress != ETH_ADDRESS ? toToken.balanceOf(address(this)) : address(this).balance) - prevBalance,
            'Bought amound does does not match'
        );

        // If we are converting from a token, remove the approve
        if (_fromTokenAddress != ETH_ADDRESS) require(fromToken.approve(address(tokenConverter), 0), 'Error removing token approve');

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
        Returns how much RCN is required for a given lend
    */
    function getRequiredRcnLend(
        address _loanManagerAddress,
        address _lenderCosignerAddress,
        bytes32 _requestId,
        uint256 _amountToPay,
        bytes memory _oracleData,
        bytes memory _cosignerData
    ) internal returns (uint256) {
        // Load loan manager and id
        LoanManager loanManager = LoanManager(_loanManagerAddress);

        // Load cosigner of loan
        Cosigner cosigner = Cosigner(_lenderCosignerAddress);

        // If loan has a cosigner, sum the cost
        uint256 required;
        if (_lenderCosignerAddress != address(0)) {
            required = required.add(cosigner.cost(_loanManagerAddress, uint256(_requestId), _cosignerData, _oracleData));
        }

        // Load the  Oracle rate and convert required        
        if (_oracleData.length > 0) {
            RateOracle rateOracle = RateOracle(loanManager.getOracle(uint256(_requestId)));
            (uint256 _tokens, uint256 _equivalent) = rateOracle.readSample(_oracleData);
            required = required.add(_toToken(_amountToPay, _tokens, _equivalent));
        }

        return required; 
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
        uint256 _tokenCost,
        uint256 _etherCost
    ) private {
        // Handle both ETH and tokens
        if (_token == ETH_ADDRESS) {
            // If ETH, require msg.value to be at least the required _etherCost
            require(msg.value >= _etherCost, 'Error pulling ETH etherCost');
            // Return any exceding ETH, if any
            if (msg.value > _etherCost) {
                msg.sender.transfer(msg.value - _etherCost);
            }
        } else {
            // If tokens, only perform a transferFrom
            require(IERC20(_token).transferFrom(msg.sender, address(this), _tokenCost), 'Error pulling token amount');
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
