pragma solidity 0.5.10;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import 'openzeppelin-solidity/contracts/math/SafeMath.sol';
import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';
import './interfaces/Cosigner.sol';
import './interfaces/diaspore/DebtEngine.sol';
import './interfaces/diaspore/LoanManager.sol';
import './interfaces/token/TokenConverter.sol';
import './interfaces/RateOracle.sol';
import './safe/SafeERC20.sol';

/// @title  Converter Ramp
/// @notice for conversion between different assets, use TokenConverter 
///         contract as abstract layer for convert different assets.
/// @dev All function calls are currently implemented without side effects
contract ConverterRamp is Ownable {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice address to identify operations with ETH 
    address public constant ETH_ADDRESS = address(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    event Return(address _token, address _to, uint256 _amount);
    event ReadedOracle(address _oracle, uint256 _tokens, uint256 _equivalent);

    
    /// @notice pays a loan using _fromTokens
    /// @param _converter converter to use for swapping (uniswap, kyber, bancor, etc)
    /// @param _fromToken token address to convert
    /// @param _loanManagerAddress address of diaspore LoanManagaer
    /// @param _debtEngineAddress address of diaspore LoanManagaer 
    /// @param _payFrom registering pay address 
    /// @param _requestId loan id to pay
    /// @param _oracleData data signed by ripio oracle
    function pay(
        address _converter,
        address _fromToken,
        address _loanManagerAddress,
        address _debtEngineAddress,
        address _payFrom,
        bytes32 _requestId,
        bytes calldata _oracleData
    ) external payable {
        
        /// load RCN IERC20, we need it to pay
        IERC20 token = LoanManager(_loanManagerAddress).token();

        /// get amount required, in RCN, for payment
        uint256 amount = getRequiredRcnPay(
            _loanManagerAddress,
            _requestId, 
            _oracleData
        );
        
        /// converter using token converter
        convertSafe(_converter, _loanManagerAddress, _fromToken, address(token), amount);

        /// pay loan
        DebtEngine debtEngine = DebtEngine(_debtEngineAddress);
        require(token.safeApprove(_debtEngineAddress, amount), "error on payment approve");
        uint256 prevTokenBal = token.balanceOf(address(this));
        debtEngine.pay(_requestId, amount, _payFrom, _oracleData);

        require(token.approve(_debtEngineAddress, 0), "error removing the payment approve");
        require(token.balanceOf(address(this)) == prevTokenBal - amount, "the contract balance should be the previous");
    }

    /// @notice Lends a loan using fromTokens, transfer loan ownership to msg.sender
    /// @param _converter converter to use for swapping (uniswap, kyber, bancor, etc)
    /// @param _fromToken token address to convert
    /// @param _loanManagerAddress address of diaspore LoanManagaer
    /// @param _lenderCosignerAddress address of diaspore Cosigner 
    /// @param _debtEngineAddress address of diaspore LoanManagaer 
    /// @param _requestId loan id to pay
    /// @param _oracleData data signed by ripio oracle
    /// @param _cosignerData cosigner data
    /// @param _callbackData callback data 
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
        
        /// load RCN IERC20
        IERC20 token = LoanManager(_loanManagerAddress).token();

        /// get required RCN for lending the loan
        uint256 amount = getRequiredRcnLend(
            _loanManagerAddress, 
            _lenderCosignerAddress, 
            _requestId,  
            _oracleData, 
            _cosignerData
        );

        /// convert using token converter
        convertSafe(_converter, _loanManagerAddress, _fromToken, address(token), amount);

        uint256 prevTokenBal = token.balanceOf(address(this));

        LoanManager(_loanManagerAddress).lend(
            _requestId, 
            _oracleData, 
            _lenderCosignerAddress, 
            0, 
            _cosignerData, 
            _callbackData
        );
        

        require(token.safeApprove(_loanManagerAddress, 0), 'error removing approve');
        require(token.balanceOf(address(this)) == prevTokenBal - amount, "the contract balance should be the previous");

        /// transfer loan to msg.sender
        DebtEngine(_debtEngineAddress).transferFrom(address(this), msg.sender, uint256(_requestId));

    }

    /// @notice get the cost, in wei, of making a convertion using the value specified.
    /// @param _amount amount to calculate cost
    /// @param _converter converter to use for swap
    /// @param _fromToken token to convert
    /// @param _token RCN token address
    /// @return _tokenCost and _etherCost
    function getCost(uint _amount, address _converter, address _fromToken, address _token) public view returns (uint256, uint256)  {
    
        TokenConverter tokenConverter = TokenConverter(_converter);
        if (_fromToken == ETH_ADDRESS) {
            return tokenConverter.getPrice(_token, _amount);
        } else {
            return tokenConverter.getPrice(_fromToken, _token, _amount);
        }
       
    }

    /// @notice Converts an amount using a converter
    /// @dev orchestrator between token->token, eth->token
    function convertSafe(
        address _converter,
        address _loanManagerAddress,
        address _fromToken,
        address _token,
        uint256 _amount
    ) internal returns (uint256 bought) {
        
        (uint256 tokenCost, uint256 etherCost) = getCost(_amount, _converter, _fromToken, address(_token));
        if (_fromToken == ETH_ADDRESS) {
            ethConvertSafe(_converter, _fromToken, address(_token), _amount, tokenCost, etherCost);
        } else {
            tokenConvertSafe(_converter, _loanManagerAddress, _fromToken, address(_token), _amount, tokenCost, etherCost);
        }
    }

    /// @dev not trusting the converter, validates all convertions using the token contract.
    ///      Token convertions
    function tokenConvertSafe(
        address _converter,
        address _loanManagerAddress,
        address _fromTokenAddress,
        address _toTokenAddress,
        uint256 _amount,
        uint256 _tokenCost,
        uint256 _etherCost
    ) internal returns (uint256 bought) {
        
        IERC20 fromToken = IERC20(_fromTokenAddress);
        IERC20 toToken = IERC20(_toTokenAddress);
        TokenConverter tokenConverter = TokenConverter(_converter);
        
        /// pull tokens to convert
        require(fromToken.safeTransferFrom(msg.sender, address(this), _tokenCost), 'Error pulling token amount');

        /// safe approve tokens to tokenConverter
        require(fromToken.safeApprove(address(tokenConverter), _tokenCost), 'Error approving token transfer');

        /// store the previus balance after conversion to validate
        uint256 prevBalance = toToken.balanceOf(address(this));

        /// call convert in token converter
        tokenConverter.convert(fromToken, toToken, _amount, _tokenCost, _etherCost, msg.sender);

        /// token balance should have increased by amount
        require(_amount == toToken.balanceOf(address(this)) - prevBalance, 'Bought amound does does not match');

        /// if we are converting from a token, remove the approve
        require(fromToken.safeApprove(address(tokenConverter), 0), 'Error removing token approve');

        /// approve token to loan manager
        require(toToken.safeApprove(_loanManagerAddress, _tokenCost), 'Error approving lend token transfer');

    }

    /// @dev not trusting the converter, validates all convertions using the token contract.
    ///      ETH convertions
    function ethConvertSafe(
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

        /// store the previus balance after conversion to validate
        uint256 prevBalance = address(this).balance;

        /// call convert in token converter
        tokenConverter.convert.value(_amount)(fromToken, toToken, _amount, _tokenCost, _etherCost, msg.sender);

    }

    /// @notice returns how much RCN is required for a given lend
    function getRequiredRcnLend(
        address _loanManagerAddress,
        address _lenderCosignerAddress,
        bytes32 _requestId,
        bytes memory _oracleData,
        bytes memory _cosignerData
    ) internal returns (uint256) {
        
        /// load loan manager and id
        LoanManager loanManager = LoanManager(_loanManagerAddress);
        uint256 amount = loanManager.getAmount(_requestId);

        /// load cosigner of loan
        Cosigner cosigner = Cosigner(_lenderCosignerAddress);

        /// if loan has a cosigner, sum the cost
        if (_lenderCosignerAddress != address(0)) {
            amount = amount.add(cosigner.cost(_loanManagerAddress, uint256(_requestId), _cosignerData, _oracleData));
        }

        /// load the  Oracle rate and convert required   
        address oracle = loanManager.getOracle(uint256(_requestId))     ;
        return getCurrencyToToken(oracle, amount, _oracleData);
    }

    /// @notice returns how much RCN is required for a given pay
    function getRequiredRcnPay(
        address _loanManagerAddress,
        bytes32 _requestId,
        bytes memory _oracleData
    ) internal returns (uint256 _result) {
        
        /// Load LoanManager and ID
        LoanManager loanManager = LoanManager(_loanManagerAddress);
        uint256 amount = loanManager.getAmount(_requestId);
        /// Read loan oracle
        address oracle = loanManager.getOracle(uint256(_requestId));
        return getCurrencyToToken(oracle, amount, _oracleData);

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
        return tokens.mul(_amount) / equivalent;
    }
}
