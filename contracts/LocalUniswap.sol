pragma solidity ^0.5.4;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "./IUniswap.sol";

contract SampleToken is ERC20 {
    function mint(uint amount) public {
        _mint(msg.sender, amount);
    }
}

contract  DummyDeposit {
    function deposit(uint x) public {
//        require(x==1234,"test revert string");
    }
    function token() public returns (address) {
        return address(new SampleToken());
    }
}

//naive, no-calculation swapper.
// the exchange rate is fixed.
// call addLiquidity or transfer (params ignored) to add eth.
contract LocalUniswap is IUniswap {
    IERC20 token;
    constructor() public payable {
        token = new SampleToken();
        require( msg.value> 0, "must specify liquidity");
    }

    function () external payable {}

    function tokenAddress (  ) external view returns ( address out ) {
        return address(token);
    }

    function addLiquidity ( uint256 min_liquidity, uint256 max_tokens, uint256 deadline ) external payable returns ( uint256 out ) {
        min_liquidity;
        max_tokens;
        deadline;
        return 0;
    }

    event SwapTokensToEth(address msgsender, uint tokensToSell, uint tokAllowance, uint eth_bought, uint ethbal, int tokbal);

    function tokenToEthSwapOutput ( uint256 eth_bought, uint256 max_tokens, uint256 deadline ) public returns ( uint256 out ) {
        (max_tokens, deadline);
        uint tokensToSell = getTokenToEthOutputPrice(eth_bought);

        emit SwapTokensToEth(msg.sender, tokensToSell, token.allowance(msg.sender,address(this)), eth_bought, msg.sender.balance, int(token.balanceOf(msg.sender)-tokensToSell));
        token.transferFrom(msg.sender, address(this), tokensToSell);
        require(address(this).balance > eth_bought, "not enough liquidity");
        msg.sender.transfer(eth_bought);
        return tokensToSell;
    }

    function getTokenToEthInputPrice ( uint256 tokens_sold ) external view returns ( uint256 out ) {
        return tokens_sold;
    }

  function tokenToEthTransferOutput ( uint256 eth_bought, uint256 max_tokens, uint256 deadline, address recipient ) external returns ( uint256 out ) {
      (max_tokens,deadline,recipient);
    return getTokenToEthOutputPrice(eth_bought);
  }

    function getTokenToEthOutputPrice ( uint256 eth_bought ) public view returns ( uint256 out ) {
        //assume 200 DAI for 1 eth..
        return eth_bought*123;
    }
}


library uni{
  function asd() internal returns(IUniswap) { return new LocalUniswap(); }
}
