pragma solidity 0.5.10;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


interface TokenConverter {

    /// @notice Converts an amount 
    ///         a. swap the user's ETH to IERC20 token or 
    ///         b. swap the user's IERC20 token to another IERC20 token or
    /// @param _inToken source token contract address
    /// @param _outToken destination token contract address
    /// @param _amount amount of source tokens
    /// @param _tokenCost amount of source _tokenCost
    /// @param _etherCost amount of source _etherCost
    /// @param _origin address to transfer exceding eth
    /// @dev _origin and _recipient can be different.
    function convert(
        IERC20 _inToken,
        IERC20 _outToken,
        uint256 _amount,
        uint256 _tokenCost,
        uint256 _etherCost,
        address payable _origin
    ) external payable;

    /// @notice get price, in wei, of making a payment of the specified value 
    ///         in this contract's configured payment token.
    /// @dev ETH -> Token
    function getPrice(
        address _outToken,
        uint256 _amount
    ) external view returns (uint256, uint256);

    /// @notice get price, in wei, of making a payment of the specified value 
    ///         in this contract's configured payment token.
    /// @dev Token -> Token
    function getPrice(
        address _token,
        address _outToken,
        uint256 _amount
    ) external view returns (uint256, uint256);

}
