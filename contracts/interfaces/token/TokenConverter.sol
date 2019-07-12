pragma solidity 0.5.10;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


interface TokenConverter {

    function convert(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _fromAmount,
        uint256 _minReturn
    ) external payable returns (uint256 amount);

    function getReturn(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _fromAmount
    ) external returns (uint256 amount);

}
