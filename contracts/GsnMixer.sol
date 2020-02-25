pragma solidity ^0.5.4;

import "@0x/contracts-utils/contracts/src/LibBytes.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openeth/gsn/contracts/RelayRecipient.sol";
import "./IUniswap.sol";
import "./ITornado.sol";

contract IDAI is IERC20 {
    function permit(address holder, address spender, uint256 nonce, uint256 expiry,
                bool allowed, uint8 v, bytes32 r, bytes32 s) external;
    mapping (address => uint)                      public nonces;
}


//Wrapper contract for Tornado Mixer
// this way, we add GSN support for Tornado, without modifying the original contracts.
// all payments are in tokens, using Uniswap
// It is simple for a mixer, since the mixer itself doesn't really care about the msg.sender
// (that's almost true: it assumes it has Approval to withdraw tokens from it. This means all deposits
// go through the GsnMixer)
// variable - a GSN-aware contract has to use a helper method getSender() instead of msg.sender.

contract GsnMixer is Ownable, RelayRecipient {

    //relaying withdraw fee in tokens (1 DAI)
    // (taken out of the deposited value)
    uint public withdrawFee = 1 ether;
    IUniswap uniswap;

    constructor(IUniswap _uniswap, address hub) public {
      uniswap=_uniswap;
      setHub(hub);
    }

    function setHub(address hub) onlyOwner public {
      setRelayHub(IRelayHub(hub));
    }

    event Received(uint value, bytes data);
    event Withdrawn(uint value);

    function () payable external {
      emit Received(msg.value, msg.data);
    }

    function withdrawEth() public onlyOwner {
      emit Withdrawn(address(this).balance);
      msg.sender.transfer(address(this).balance);
    }

    //"internal"
    function splitRSV(bytes memory sig) pure public
          returns( bytes32 r, bytes32 s, uint8 v) {

        bytes1 b1;
        //append buffer with zeros first, to be able to read 32-chunk of last element
        (r,s,b1) = abi.decode(abi.encodePacked(sig,uint(0)), (bytes32, bytes32,bytes1));
        //TODO: do we need >>(256-8) ?
        v = uint8(b1);
    }

    function approveOwner(IERC20 token) internal {
      if ( token.allowance(address(this),owner())==0 ) {
        token.approve(owner(), uint(-1));
      }
    }

    event Permit(bool success, string err);

    function getError(bytes memory err) internal pure returns (string memory ret) {
      if ( err.length < 4+32 )
        return string(err);
      (ret) = abi.decode(LibBytes.slice(err,4,err.length), (string));
    }

    function permit(IDAI token, address holder, address spender, uint256 nonce, uint256 expiry,
                    bool allowed, bytes calldata sig) external {

        approveOwner(token);

        ( bytes32 r, bytes32 s, uint8 v )  = splitRSV(sig);
        if ( nonce == 0 ) 
          nonce = token.nonces(holder);

        (bool success, bytes memory ret ) = address(token).call(
            abi.encodeWithSelector(token.permit.selector, 
              holder, spender, nonce, expiry, allowed, v,r,s ));
        emit Permit(success, getError(ret) );
    }

    //we got the DAI deposit from the client. so forward it, after giving the mixer allowance
    function deposit(ITornado tornado, bytes32 _id, bytes calldata permitSig) external {
        IDAI token = IDAI(tornado.token());
        if ( permitSig.length>0 ) {
          this.permit(token, getSender(), address(this), token.nonces(getSender()), 0, true, permitSig);
        }

        approveOwner(token);
        
        token.transferFrom( getSender(), address(this), tornado.denomination()+withdrawFee);
        //allow the mixer to pull the tokens from us..
        if ( token.allowance(address(this), address(tornado)) ==0 ) {
            token.approve(address(tornado), uint(-1));
        }
        tornado.deposit(_id);
    }

    function withdraw(ITornado tornado, bytes calldata _proof, bytes32 _root, bytes32 _nullifierHash, 
        address payable _recipient, address payable _relayer, uint256 _fee, uint256 _refund) external {

        tornado.withdraw(_proof, _root, _nullifierHash, 
            _recipient, _relayer, _fee, _refund);

    }

    function acceptRelayedCall(
        address relay,
        address from,
        bytes calldata encodedFunction,
        uint256 transactionFee,
        uint256 gasPrice,
        uint256 gasLimit,
        uint256 nonce,
        bytes calldata approvalData,
        uint256 maxPossibleCharge
    )
    external
    view
    returns (uint256, bytes memory) {
      (relay, from, encodedFunction, transactionFee, gasPrice, gasLimit, nonce, approvalData, maxPossibleCharge);

      // bytes4 sig = LibBytes.readBytes4(encodedFunction,0);
      // unit tokenPrecharge = uniswap.getTokenToEthOutputPrice(maxPossibleCharge);
      // if ( sig == this.deposit.selector) {
      //   ITornado tornado = address(GsnUtils.getParam(encodedFunction,0));

      // } else if ( sig == this.withdraw.selector) {

      // } else if ( sig == this.permit.selector) {

      // } else {
      //   return (99, "gsnmixer: invalid method");
      // }

      //TODO:
      //  deposit:
      //    - validate caller has enough tokens (including relayer fee)
      //  withdraw: 
      //    - validate relayer and fee fields are set
      //    - validate not spent yet
      //    - GSN2 - call verifyProof()
      uint tokenPrecharge=0;
      bytes memory context = abi.encode(tokenPrecharge);
      return(0, context);
    }

    function preRelayedCall(bytes calldata context) external returns (bytes32) {
      uint256 tokenPrecharge = abi.decode(context, (uint256));
      (tokenPrecharge);
      //TODO: pre-charge
      return bytes32(0);
    }

    function postRelayedCall(bytes calldata context, bool success, uint actualCharge, bytes32 preRetVal) external {
      (success, actualCharge, preRetVal);
      uint256 tokenPrecharge = abi.decode(context, (uint256));

      (tokenPrecharge);
      //TODO: refund
    }

}

contract KovanGsnMixer is GsnMixer {

  address constant hubAddr = 0xD216153c06E857cD7f72665E0aF1d7D82172F494;
  address constant cDaiUniswapExchange = 0x613639E23E91fd54d50eAfd6925AF2Ed6701A46b;

  constructor() GsnMixer(IUniswap(cDaiUniswapExchange), hubAddr) public {
  }
}

