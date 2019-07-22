pragma solidity 0.5.10;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


interface TokenConverter {

    function convert(
        IERC20 _token,
        IERC20 _outToken,
        uint256 _amount,
        uint256 _tokenCost,
        uint256 _etherCost,
        address payable _origin
    ) external payable;

    function getPrice(
        address _outToken,
        uint256 _amount
    ) external view returns (uint256, uint256);

    function getPrice(
        address _token,
        address _outToken,
        uint256 _amount
    ) external view returns (uint256, uint256);

}
