import './../interfaces/token/TokenConverter.sol';
import './../interfaces/uniswap/UniswapFactoryInterface.sol';
import './../interfaces/uniswap/UniswapExchangeInterface.sol';
import './../safe/SafeERC20.sol';
import './../safe/SafeExchange.sol';
import 'openzeppelin-solidity/contracts/math/SafeMath.sol';
import 'openzeppelin-solidity/contracts/token/ERC20/IERC20.sol';
import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';
pragma solidity 0.5.10;

/// @notice proxy between ConverterRamp and Uniswap
///         accepts tokens and ether, converts these to the desired token, 
///         and makes approve calls to allow the recipient to transfer those 
///         tokens from the contract.
/// @author Joaquin Pablo Gonzalez (jpgonzalezra@gmail.com)
contract UniswapProxy is TokenConverter, Ownable {
    
    using SafeMath for uint256;
    using SafeExchange for UniswapExchangeInterface;
    using SafeERC20 for IERC20;

    event Swap(address indexed _sender, IERC20 _token, IERC20 _outToken, uint _amount);
    event WithdrawTokens(address _token, address _to, uint256 _amount);
    event WithdrawEth(address _to, uint256 _amount);
    event SetUniswap(address _uniswapFactory);

    /// @notice address to identify operations with ETH 
    IERC20 constant internal ETH_TOKEN_ADDRESS = IERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    /// @notice registry of ERC20 tokens that have been added to the system 
    ///         and the exchange to which they are associated.
    UniswapFactoryInterface factory;

    constructor (address _uniswapFactory) public {
        factory = UniswapFactoryInterface(_uniswapFactory);
        emit SetUniswap(_uniswapFactory);
    }
    
    /// @notice get price to swap token to another token
    /// @return _tokenCost, _etherCost, _inExchange
    /// @dev  internal method.
    function price(
        address _token,
        address _outToken,
        uint256 _amount
    ) internal view returns (uint256, uint256, UniswapExchangeInterface) {
        UniswapExchangeInterface inExchange =
          UniswapExchangeInterface(factory.getExchange(_token));
        UniswapExchangeInterface outExchange =
          UniswapExchangeInterface(factory.getExchange(_outToken));

        uint256 etherCost = outExchange.getEthToTokenOutputPrice(_amount);
        uint256 tokenCost = inExchange.getTokenToEthOutputPrice(etherCost);

        return (tokenCost, etherCost, inExchange);
    }

    /// @notice get price to swap eth to token
    /// @return _etherCost, _exchange
    /// @dev  internal method.
    function price(
        address _outToken,
        uint256 _amount
    ) internal view returns (uint256, UniswapExchangeInterface) {
      UniswapExchangeInterface exchange =
        UniswapExchangeInterface(factory.getExchange(_outToken));

      return (exchange.getEthToTokenOutputPrice(_amount), exchange);
    }

    /// @notice change uniswap factory address
    /// @param _uniswapFactory address
    /// @return returns true if everything was correct
    function setUniswapFactory(address _uniswapFactory) external onlyOwner returns (bool) {
        factory = UniswapFactoryInterface(_uniswapFactory);
        emit SetUniswap(_uniswapFactory);
        return true;
    }

    /// @notice get price for swap token to token
    /// @return _tokenCost, _etherCost, _inExchange
    function getPrice(
        address _token,
        address _outToken,
        uint256 _amount
    ) public view returns (uint256, uint256) {
        
        (
            uint256 tokenCost, 
            uint256 etherCost,
        ) = price(address(_token), address(_outToken), _amount);

        return (tokenCost, etherCost);
    }

    /// @notice get price for swap eth to token
    /// @return _tokenCost, _etherCost, _inExchange
    function getPrice(
        address _outToken,
        uint256 _amount
    ) public view returns (uint256, uint256) {
        
        (
            uint256 etherCost,
        ) = price(address(_outToken), _amount);
        
        return (0, etherCost);

    }

    /// @notice Converts an amount 
    ///         a. swap the user's ETH to IERC20 token or 
    ///         b. swap the user's IERC20 token to another IERC20 token
    /// @param _inToken source token contract address
    /// @param _outToken destination token contract address
    /// @param _amount amount of source tokens
    /// @param _tokenCost amount of source _tokenCost
    /// @param _etherCost amount of source _etherCost
    /// @param _origin address to transfer leftover eth
    /// @dev _origin and _recipient can be different.
    function convert(
        IERC20 _inToken,
        IERC20 _outToken, 
        uint256 _amount,
        uint256 _tokenCost,
        uint256 _etherCost, 
        address payable _origin
    ) external payable {   

        address sender = msg.sender;
        if (_inToken == ETH_TOKEN_ADDRESS && _outToken != ETH_TOKEN_ADDRESS) {
            execSwapEtherToToken(_outToken, _amount, _etherCost, sender, _origin);
        } else {
            require(msg.value == 0, "eth not required");    
            execSwapTokenToToken(_inToken, _amount, _tokenCost, _etherCost, _outToken, sender);
        }

        emit Swap(msg.sender, _inToken, _outToken, _amount);
        
    }

    /// @notice Swap the user's ETH to IERC20 token
    /// @param _outToken source token contract address
    /// @param _amount amount of source tokens
    /// @param _etherCost amount of source _etherCost
    /// @param _recipient address to send swapped tokens to
    /// @param _origin address to transfer leftover eth
    function execSwapEtherToToken(
        IERC20 _outToken, 
        uint _amount,
        uint _etherCost, 
        address _recipient, 
        address payable _origin
    ) public payable {
        
        UniswapExchangeInterface exchange = UniswapExchangeInterface(factory.getExchange(address(_outToken)));
        
        require(msg.value >= _etherCost, "insufficient ether sent.");
        exchange.swapEther(_amount, _etherCost, block.timestamp + 1, _outToken);

        require(_outToken.safeTransfer(_recipient, _amount), "error transfer tokens"); 
        // Return any exceding ETH, if any
        _origin.transfer(msg.value.sub(_etherCost));
    }

    /// @notice swap the user's IERC20 token to another IERC20 token
    /// @param _token source token contract address
    /// @param _amount amount of source tokens
    /// @param _tokenCost amount of source _tokenCost
    /// @param _etherCost amount of source _etherCost
    /// @param _outToken destination token contract address
    /// @param _recipient address to send swapped tokens to
    function execSwapTokenToToken(
        IERC20 _token, 
        uint256 _amount,
        uint256 _tokenCost,
        uint256 _etherCost, 
        IERC20 _outToken, 
        address _recipient
    ) internal {

        UniswapExchangeInterface exchange = UniswapExchangeInterface(factory.getExchange(address(_token)));
        /// Check that the player has transferred the token to this contract
        require(_token.safeTransferFrom(msg.sender, address(this), _tokenCost), "error pulling tokens");

        /// Set the spender's token allowance to tokenCost
        _token.safeApprove(address(exchange), _tokenCost);

        /// safe swap tokens
        exchange.swapTokens(_amount, _tokenCost, _etherCost, block.timestamp + 1, _outToken);
        require(_outToken.safeTransfer(_recipient, _amount), "error transfer tokens");        
    }

    function() external payable {}

}