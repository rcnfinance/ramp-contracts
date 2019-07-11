import "./../interfaces/token/TokenConverter.sol";
import "./../interfaces/uniswap/UniswapFactoryInterface.sol";
import "./../interfaces/uniswap/UniswapExchangeInterface.sol";
import 'openzeppelin-solidity/contracts/math/SafeMath.sol';
import 'openzeppelin-solidity/contracts/token/ERC20/IERC20.sol';
import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';

pragma solidity 0.5.10;


contract UniswapProxy is TokenConverter, Ownable {
    
    using SafeMath for uint256;

    uint public constant WAD = 10 ** 18;
    IERC20 constant internal ETH_TOKEN_ADDRESS = IERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    UniswapFactoryInterface uniswapFactory;

    event Swap(address indexed sender, IERC20 srcToken, IERC20 destToken, uint amount);

    event WithdrawTokens(address _token, address _to, uint256 _amount);
    event WithdrawEth(address _to, uint256 _amount);
    event SetUniswap(address _uniswap);

    constructor (address _uniswap) public {
        uniswapFactory = UniswapFactoryInterface(_uniswap);
        emit SetUniswap(_uniswap);
    }

    function setUniswap(address _uniswap) external onlyOwner returns (bool) {
        uniswapFactory = UniswapFactoryInterface(_uniswap);
        emit SetUniswap(_uniswap);
        return true;
    }
    
    function getReturn(
        Token from,
        Token to, 
        uint256 srcQty
    ) external returns (uint256) {
        return getExpectedRate(IERC20(address(from)), IERC20(address(to)), srcQty);
        // return (srcQty * getExpectedRate(address(from), address(to), srcQty)) / 10 ** 18; // TODO: ?
    }

    function getExpectedRate(IERC20 from, IERC20 to, uint srcQty) view internal returns (uint) {
        if (from == ETH_TOKEN_ADDRESS) {
            address uniswapTokenAddress = uniswapFactory.getExchange(address(to));
            return wdiv(UniswapExchangeInterface(uniswapTokenAddress).getEthToTokenInputPrice(srcQty), srcQty);
        } else if (to == ETH_TOKEN_ADDRESS) {
            address uniswapTokenAddress = uniswapFactory.getExchange(address(from));
            return wdiv(UniswapExchangeInterface(uniswapTokenAddress).getTokenToEthInputPrice(srcQty), srcQty);
        } else {
            uint ethBought = UniswapExchangeInterface(uniswapFactory.getExchange(address(from))).getTokenToEthInputPrice(srcQty);
            return wdiv(UniswapExchangeInterface(uniswapFactory.getExchange(address(to))).getEthToTokenInputPrice(ethBought), ethBought);
        }
    }

    // TODO:
    function convert(
        Token from,
        Token to, 
        uint256 srcQty, 
        uint256 minReturn
    ) external payable returns (uint256 destAmount) {

        IERC20 srcToken = IERC20(address(from));
        IERC20 destToken = IERC20(address(to));       

        address sender = msg.sender;
        if (srcToken == ETH_TOKEN_ADDRESS && destToken != ETH_TOKEN_ADDRESS) {
            require(msg.value == srcQty, "ETH not enought");
            destAmount = execSwapEtherToToken(destToken, srcQty, sender);
        } else if (srcToken != ETH_TOKEN_ADDRESS && destToken == ETH_TOKEN_ADDRESS) {
            require(msg.value == 0, "ETH not required");    
            destAmount = execSwapTokenToEther(srcToken, srcQty, sender);
        } else {
            require(msg.value == 0, "ETH not required");    
            destAmount = execSwapTokenToToken(srcToken, srcQty, destToken, sender);
        }

        require(destAmount > minReturn, "Return amount too low");   
        emit Swap(msg.sender, srcToken, destToken, destAmount);
    
        return destAmount;
    }

    /*
    @notice Swap the user's ETH to IERC20 token
    @param token destination token contract address
    @param destAddress address to send swapped tokens to
    */
    function execSwapEtherToToken (IERC20 token, uint srcQty, address destAddress) public payable returns(uint) {
        
        address uniswapTokenAddress = uniswapFactory.getExchange(address(token));
        // Send the swapped tokens to the destination address and send the swapped tokens to the destination address
        uint tokenAmount = UniswapExchangeInterface(uniswapTokenAddress).
                ethToTokenTransferInput.value(srcQty)(1, block.timestamp + 1, destAddress);
        
        return tokenAmount;
    }

    /*
    @notice Swap the user's IERC20 token to ETH
    @param token source token contract address
    @param tokenQty amount of source tokens
    @param destAddress address to send swapped ETH to
    */
    function execSwapTokenToEther (IERC20 token, uint tokenQty, address destAddress) internal returns(uint) {
        
        // Check that the player has transferred the token to this contract
        require(token.transferFrom(msg.sender, address(this), tokenQty), "Error pulling tokens");

        // Set the spender's token allowance to tokenQty
        address uniswapTokenAddress = uniswapFactory.getExchange(address(token));
        token.approve(uniswapTokenAddress, tokenQty);

        // Swap the IERC20 token to ETH and send the swapped ETH to the destination address
        uint ethAmount = UniswapExchangeInterface(uniswapTokenAddress).tokenToEthTransferInput(tokenQty, 1, block.timestamp + 1, destAddress);
        
        return ethAmount;
    }

    /*
    @dev Swap the user's IERC20 token to another IERC20 token
    @param srcToken source token contract address
    @param srcQty amount of source tokens
    @param destToken destination token contract address
    @param destAddress address to send swapped tokens to
    */
    function execSwapTokenToToken(
        IERC20 srcToken, 
        uint256 srcQty, 
        IERC20 destToken, 
        address destAddress
    ) internal returns (uint) {

        // Check that the player has transferred the token to this contract
        require(srcToken.transferFrom(msg.sender, address(this), srcQty), "Error pulling tokens");

        // Set the spender's token allowance to srcQty
        address uniswapTokenAddress = uniswapFactory.getExchange(address(destToken));
        srcToken.approve(uniswapTokenAddress, srcQty);

        // Swap the IERC20 token to IERC20 and send the swapped tokens to the destination address
        uint destAmount = UniswapExchangeInterface(uniswapTokenAddress).tokenToTokenTransferInput(
            srcQty, 
            1,  //TODO: 
            1,  //TODO:
            block.timestamp + 1, 
            destAddress, 
            address(destToken)
        );

        return destAmount;
    }

    function withdrawTokens(
        Token _token,
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        emit WithdrawTokens(address(_token), _to, _amount);
        return _token.transfer(_to, _amount);
    }

    function withdrawEther(
        address payable _to,
        uint256 _amount
    ) external onlyOwner {
        emit WithdrawEth(_to, _amount);
        _to.transfer(_amount);
    }

    function() external payable {}

    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = ((x.mul(WAD)).add(y / 2)) / y;
    }
}