pragma solidity ^0.5.4;

//minimal uniswap we need:
interface IUniswap {
  function tokenAddress() view external returns( address );

  function tokenToEthSwapOutput ( uint256 eth_bought, uint256 max_tokens, uint256 deadline ) external returns ( uint256 out );
  function tokenToEthTransferOutput ( uint256 eth_bought, uint256 max_tokens, uint256 deadline, address recipient ) external returns ( uint256 out );

  function getTokenToEthOutputPrice ( uint256 eth_bought ) external view returns ( uint256 out );
  function getTokenToEthInputPrice ( uint256 tokens_sold ) external view returns ( uint256 out );
}
