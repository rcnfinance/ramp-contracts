# Ramps

Ramps allow lend and pay to be made with any ERC-20 token while the protocol receiving RCN their token.

TokenConverter accepts tokens and ether, converts these to the RCN token, and makes corresponding calls.


## Install

    npm i

## Compile

    npm run compile

Compiled contracts will be written to the `build` directory as 
[Truffle](https://truffleframework.com)
[build artifacts](https://truffleframework.com/docs/truffle/getting-started/compiling-contracts#build-artifacts).

## Usage

A UniswapProxy contract is deployed with the following configuration parameters:

  * address factory: The address of the Uniswap factory contract to use to access swappable liquidity.

A ConverterRamp contract is deployed without configuration parameters.
