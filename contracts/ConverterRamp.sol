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
    event ReadedOracle(address _oracle, uint256 _tokens, uint256 _equivalent);

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
        bytes calldata _oracleData
    ) external payable {
        // Load RCN IERC20, we need it to pay
        IERC20 token = LoanManager(_loanManagerAddress).token();

        // Get amount required, in RCN, for payment
        uint256 amount = getRequiredRcnPay(
            _loanManagerAddress,
            _requestId, 
            _oracleData
        );
        
        (uint256 tokenCost, uint256 etherCost) = getCost(amount, _converter, _fromToken, address(token));
        pullAmount(_fromToken, tokenCost, etherCost);

        // Convert using token _converter
        convertSafe(_converter, _fromToken, address(token), amount, tokenCost, etherCost);

        // Pay loan
        DebtEngine debtEngine = DebtEngine(_debtEngineAddress);
        require(token.approve(_debtEngineAddress, amount), "Error on payment approve");
        debtEngine.pay(_requestId, amount, _payFrom, _oracleData);
        require(token.approve(_debtEngineAddress, 0), "Error removing the payment approve");
        
        
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
            _oracleData, 
            _cosignerData
        );

        // Pull required _fromToken amount to sell
        (uint256 tokenCost, uint256 etherCost) = getCost(amount, _converter, _fromToken, address(token));
        pullAmount(_fromToken, tokenCost, etherCost);

        // Convert _fromToken into RCN
        convertSafe(_converter, _fromToken, address(token), amount, tokenCost, etherCost);

        // Lend loan
        require(token.approve(_loanManagerAddress, tokenCost), 'Error approving lend token transfer');
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
        // DebtEngine(_debtEngineAddress).transferFrom(address(this), msg.sender, uint256(_requestId));

        // The contract balance should remain the same
        require(token.balanceOf(address(this)) == 0, 'The contract balance should not change');

    }

    function getCost(uint _amount, address _converter, address _fromToken, address _token) public view returns (uint256, uint256)  {
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
        bytes memory _oracleData,
        bytes memory _cosignerData
    ) internal returns (uint256) {
        // Load loan manager and id
        LoanManager loanManager = LoanManager(_loanManagerAddress);
        uint256 amount = loanManager.getAmount(_requestId);

        // Load cosigner of loan
        Cosigner cosigner = Cosigner(_lenderCosignerAddress);

        // If loan has a cosigner, sum the cost
        if (_lenderCosignerAddress != address(0)) {
            amount = amount.add(cosigner.cost(_loanManagerAddress, uint256(_requestId), _cosignerData, _oracleData));
        }

        // Load the  Oracle rate and convert required   
        address oracle = loanManager.getOracle(uint256(_requestId))     ;
        return getCurrencyToToken(oracle, amount, _oracleData);
    }

    /*
        Returns how much RCN is required for a given pay
    */
    function getRequiredRcnPay(
        address _loanManagerAddress,
        bytes32 _requestId,
        bytes memory _oracleData
    ) internal returns (uint256 _result) {
        // Load LoanManager and ID
        LoanManager loanManager = LoanManager(_loanManagerAddress);
        uint256 amount = loanManager.getAmount(_requestId);
        // Read loan oracle
        address oracle = loanManager.getOracle(uint256(_requestId));
        return getCurrencyToToken(oracle, amount, _oracleData);

    }

    function getCurrencyToToken(
        address _oracle,
        uint256 _amount,
        bytes memory _oracleData
    ) internal returns (uint256) {
        if (_oracle == address(0)) return _amount;
        (uint256 tokens, uint256 equivalent) = RateOracle(_oracle).readSample(_oracleData);

        emit ReadedOracle(_oracle, tokens, equivalent);
        return tokens.mul(_amount) / equivalent;
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
