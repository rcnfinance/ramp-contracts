import "./../interfaces/token/TokenConverter.sol";
import "./../interfaces/uniswap/Uniswap.sol";
import "./../safe/SafeERC20.sol";
import "./../safe/SafeExchange.sol";
import 'openzeppelin-solidity/contracts/math/SafeMath.sol';
import 'openzeppelin-solidity/contracts/token/ERC20/IERC20.sol';
import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';

pragma solidity 0.5.10;

//  Infinite Test Token (TEST) -> 0x2f45b6fb2f28a73f110400386da31044b2e953d4
//  Distributed Infinite Test Token (DEST) -> 0x6710d597fd13127a5b64eebe384366b12e66fdb6

contract UniswapProxy is TokenConverter, Ownable {
    
    using SafeMath for uint256;
    using SafeExchange for UniswapExchangeInterface;
    using SafeERC20 for IERC20;

    event Swap(address indexed sender, IERC20 _token, IERC20 _outToken, uint _amount);
    event WithdrawTokens(address _token, address _to, uint256 _amount);
    event WithdrawEth(address _to, uint256 _amount);
    event SetUniswap(address _uniswapFactory);

    uint public constant WAD = 10 ** 18;
    IERC20 constant internal ETH_TOKEN_ADDRESS = IERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    UniswapFactoryInterface factory; // 0x9c83dce8ca20e9aaf9d3efc003b2ea62abc08351

    constructor (address _uniswapFactory) public {
        factory = UniswapFactoryInterface(_uniswapFactory);
        emit SetUniswap(_uniswapFactory);
    }

    function setUniswapFactory(address _uniswapFactory) external onlyOwner returns (bool) {
        factory = UniswapFactoryInterface(_uniswapFactory);
        emit SetUniswap(_uniswapFactory);
        return true;
    }

    function price(
        address _token,
        address _outToken,
        uint256 _amount
    ) public view returns (uint256, uint256, UniswapExchangeInterface) {
        UniswapExchangeInterface inExchange =
          UniswapExchangeInterface(factory.getExchange(_token));
        UniswapExchangeInterface outExchange =
          UniswapExchangeInterface(factory.getExchange(_outToken));

        uint256 etherCost = outExchange.getEthToTokenOutputPrice(_amount);
        uint256 tokenCost = inExchange.getTokenToEthOutputPrice(etherCost);

        return (tokenCost, etherCost, inExchange);
    }

    function price(
        address _outToken,
        uint256 _amount
    ) public view returns (uint256, UniswapExchangeInterface) {
      UniswapExchangeInterface exchange =
        UniswapExchangeInterface(factory.getExchange(_outToken));

      return (exchange.getEthToTokenOutputPrice(_amount), exchange);
    }

    function convert(
        IERC20 _inToken,
        IERC20 _outToken, 
        uint256 _amount
    ) external payable {   

        address sender = msg.sender;
        if (_inToken == ETH_TOKEN_ADDRESS && _outToken != ETH_TOKEN_ADDRESS) {
            execSwapEtherToToken(_outToken, _amount, sender);
        } else {
            require(msg.value == 0, "ETH not required");    
            execSwapTokenToToken(_inToken, _amount, _outToken, sender);
        }

        emit Swap(msg.sender, _inToken, _outToken, _amount);
    }

    /*
    @notice Swap the user's ETH to IERC20 token
    @param _token destination token contract address
    @param _outToken address to send swapped tokens to
    */
    function execSwapEtherToToken(IERC20 _outToken, uint _amount, address recipient) public payable {
        
        (
            uint256 etherCost,
            UniswapExchangeInterface exchange
        ) = price(address(_outToken), _amount);
        
        require(msg.value >= etherCost, "Insufficient ether sent.");
        exchange.swapEther(_amount, etherCost, block.timestamp + 1, _outToken);

        _outToken.safeApprove(recipient, _amount);
        msg.sender.transfer(msg.value.sub(etherCost));
    }

    /*
    @dev Swap the user's IERC20 token to another IERC20 token
    @param _token source token contract address
    @param _amount amount of source tokens
    @param _outToken destination token contract address
    @param _recipient address to send swapped tokens to
    */
    function execSwapTokenToToken(
        IERC20 _token, 
        uint256 _amount, 
        IERC20 _outToken, 
        address _recipient
    ) internal {

        // set tokenCost and etherCost and exchange
        (
            uint256 tokenCost, 
            uint256 etherCost, 
            UniswapExchangeInterface exchange
        ) = price(address(_token), address(_outToken), _amount);

        // Check that the player has transferred the token to this contract
        require(_token.safeTransferFrom(msg.sender, address(this), tokenCost), "Error pulling tokens");

        // Set the spender's token allowance to tokenCost
        _token.safeApprove(address(exchange), tokenCost);

        // safe swap tokens
        exchange.swapTokens(_amount, tokenCost, etherCost, block.timestamp + 1, _outToken);
        _outToken.transfer(_recipient, _amount);
        
    }

    function withdrawTokens(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        emit WithdrawTokens(address(_token), _to, _amount);
        return _token.safeTransfer(_to, _amount);
    }

    function withdrawEther(
        address payable _to,
        uint256 _amount
    ) external onlyOwner {
        emit WithdrawEth(_to, _amount);
        _to.transfer(_amount);
    }

    function() external payable {}

}