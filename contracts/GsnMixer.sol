pragma solidity ^0.5.4;
pragma experimental ABIEncoderV2;

import "@0x/contracts-utils/contracts/src/LibBytes.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "@openeth/gsn/contracts/BaseRelayRecipient.sol";
import "@openeth/gsn/contracts/BaseGasSponsor.sol";
import "./IUniswap.sol";
import "./ITornado.sol";

contract IDAI is IERC20 {
    function permit(address holder, address spender, uint256 nonce, uint256 expiry,
        bool allowed, uint8 v, bytes32 r, bytes32 s) external;

    mapping(address => uint)                      public nonces;
}

//Wrapper contract for Tornado Mixer
// this way, we add GSN support for Tornado, without modifying the original contracts.
// all payments are in tokens, using Uniswap
// It is simple for a mixer, since the mixer itself doesn't really care about the msg.sender
// (that's almost true: it assumes it has Approval to withdraw tokens from it. This means all deposits
// go through the GsnMixer)
// variable - a GSN-aware contract has to use a helper method getSender() instead of msg.sender.

contract GsnMixer is Ownable, BaseRelayRecipient, BaseGasSponsor {

    mapping(address => bool) public validMixers;
    //relaying withdraw fee in tokens (1 DAI)
    // (taken out of the deposited value)
    uint public withdrawFee = 1 ether;
    IUniswap uniswap;
    IERC20 uniswaptoken;

    function getRelayHub() view internal returns (IRelayHub) {
        return relayHub;
    }
    constructor(IUniswap _uniswap, address hub) public {
        uniswap = _uniswap;
        uniswaptoken = IERC20(uniswap.tokenAddress());

        setHub(hub);

        validMixers[0xD4B88Df4D29F5CedD6857912842cff3b20C8Cfa3] = true;
        validMixers[0xFD8610d20aA15b7B2E3Be39B396a1bC3516c7144] = true;
        validMixers[0xF60dD140cFf0706bAE9Cd734Ac3ae76AD9eBC32A] = true;
        validMixers[0xdf2d3cC5F361CF95b3f62c4bB66deFe3FDE47e3D] = true;
        validMixers[0xD96291dFa35d180a71964D0894a1Ae54247C4ccD] = true;
        validMixers[0xb192794f72EA45e33C3DF6fe212B9c18f6F45AE3] = true;

    }

    function setHub(address hub) onlyOwner public {
        relayHub = IRelayHub(hub);
    }

    event Received(uint value, bytes data);
    event Withdrawn(uint value);

    function() payable external {
        emit Received(msg.value, msg.data);
    }

    function withdrawEth() public onlyOwner {
        emit Withdrawn(address(this).balance);
        msg.sender.transfer(address(this).balance);
    }

    function getRelayHubDeposit() public view returns (uint) {
        return getRelayHub().balanceOf(address(this));
    }

    /// withdraw deposit from relayHub
    function withdrawRelayHubDepositTo(uint amount, address payable target) public onlyOwner {
        getRelayHub().withdraw(amount, target);
    }

    function relayHubDeposit() public payable onlyOwner {
        getRelayHub().depositFor.value(msg.value)(address(this));
    }

    function failFunction() external {
        revert( "failedFunc" );
    }
    function testFunction() external {
        emit Permit(false,"");
    }

    //"internal"
    function splitRSV(bytes memory sig) pure public
    returns (bytes32 r, bytes32 s, uint8 v) {

        bytes1 b1;
        require( sig.length >=65, "invalid sig");
        //append buffer with zeros first, to be able to read 32-chunk of last element
        (r,s,b1) = abi.decode(abi.encodePacked(sig, uint(0)), (bytes32, bytes32, bytes1));
        //TODO: do we need >>(256-8) ?
        v = uint8(b1);
    }

    function approveOwner(IERC20 token) internal {
        if (token.allowance(address(this), owner()) == 0) {
            token.approve(owner(), uint(- 1));
        }
    }

    event Permit(bool success, string err);

    function getError(bytes memory err) internal pure returns (string memory ret) {
        if (err.length < 4 + 32)
            return string(err);
        (ret) = abi.decode(LibBytes.slice(err, 4, err.length), (string));
    }

    function permit(IDAI token, address holder, address spender, uint256 nonce, uint256 expiry,
        bool allowed, bytes calldata sig) external {

        approveOwner(token);

        (bytes32 r, bytes32 s, uint8 v) = splitRSV(sig);
        if (nonce == 0)
            nonce = token.nonces(holder);

        (bool success, bytes memory ret) = address(token).call(
            abi.encodeWithSelector(token.permit.selector,
            holder, spender, nonce, expiry, allowed, v, r, s));
        emit Permit(success, getError(ret));
    }

    function _getSender() private view returns (address) {
        if (msg.sender == address(this))
            return LibBytes.readAddress(msg.data, msg.data.length - 20);
        else
            return getSender();
    }

    //we got the DAI deposit from the client. so forward it, after giving the mixer allowance
    function deposit(ITornado tornado, bytes32 _id, bytes calldata permitSig) external {

        require(validMixers[address(tornado)], "unsupported mixer");
        address sender = _getSender();
        //for testing with checkFunctionCallable, we accept "this" as sender for the purpose of appending a sender
        IDAI token = IDAI(tornado.token());
        if (permitSig.length > 0) {
            this.permit(token, sender, address(this), token.nonces(sender), 0, true, permitSig);
        }

        approveOwner(token);

        token.transferFrom(sender, address(this), tornado.denomination() + withdrawFee);
        //allow the mixer to pull the tokens from us..
        if (token.allowance(address(this), address(tornado)) == 0) {
            token.approve(address(tornado), uint(- 1));
        }
        tornado.deposit(_id);
    }

    function withdraw(ITornado tornado, bytes calldata _proof, bytes32 _root, bytes32 _nullifierHash,
        address payable _recipient, address payable _relayer, uint256 _fee, uint256 _refund) external {

        tornado.withdraw(_proof, _root, _nullifierHash,
            _recipient, _relayer, _fee, _refund);

    }

    function acceptRelayedCall(
        GSNTypes.RelayRequest calldata relayRequest,
        bytes calldata approvalData,
        uint256 maxPossibleGas
    )
    external
    returns (uint256, bytes memory) {
        (approvalData, maxPossibleGas);

        address from = relayRequest.relayData.senderAccount;
        uint maxPossibleCharge = 1_000_000; //getRelayHub().calculateCharge(maxPossibleGas, relayRequest.gasData.gasPrice, relayRequest.gasData.pctRelayFee);

        {
            bytes memory ret = checkFunctionCallable(relayRequest.gasData.gasLimit,
                                    from, relayRequest.encodedFunction);
            ret = bytes(getError(ret));
            if (ret.length == 0 || ret[0] != '+') {
                //failed. return orignal error code.
                return (99, ret);
            }
        }

        bytes4 sel = LibBytes.readBytes4(relayRequest.encodedFunction, 0);
        if (sel != this.withdraw.selector) {
            if (uniswaptoken.balanceOf(from) < uniswap.getTokenToEthOutputPrice(maxPossibleCharge)) {
                return (101, "DAI balance too low");
            }
        }

        uint tokenPrecharge = 0;

        return (0, abi.encode(tokenPrecharge, from));
    }

    function checkFunctionCallable(uint gasLimit, address from, bytes memory encodedFunction) internal returns (bytes memory) {
        //verify we can make this call:
        (bool success, bytes memory ret) = address(this).call // .gas(gasLimit)(
            (abi.encodeWithSelector(this.checkFunctionCallable1.selector,
            abi.encodePacked(encodedFunction, from)));
        (success);
        return ret;
    }

    //check that the given function can be called successfully.
    // always revert (to revert any side-effects)
    //  "+ "- the function completed successfuly
    // other - the actual revert string of the function.
    // NOTE: we call the function from "this", not from RelayHub, so it might change the outcome.
    //  we have localSender member for that..
    function checkFunctionCallable1(bytes memory encodedFunction) public returns (bytes memory) {
        require(msg.sender == address(this), "only from acceptRelayedCall");
        (bool success, bytes memory ret) = address(this).call(encodedFunction);
        if (success) {
            revert("+ success");
        }
        revert(getError(ret));
    }

    function preRelayedCall(bytes calldata context) external returns (bytes32) {
        uint256 tokenPrecharge = abi.decode(context, (uint256));
        (tokenPrecharge);
        return bytes32(0);
    }

    function postRelayedCall(
        bytes calldata context,
        bool success,
        bytes32 preRetVal,
        uint256 gasUseWithoutPost,
        uint256 txFee,
        uint256 gasPrice
    ) external {

        (success, preRetVal, gasUseWithoutPost, txFee, gasPrice);
        (uint256 tokenPrecharge, address sender) = abi.decode(context, (uint256, address));
        if (sender == address(0)) {
            //gratis..
            return;
        }
        uint actualCharge = 500_000; // getRelayHub().calculateCharge(gasUseWithoutPost, gasPrice, txFee);
        uint tokenActualCharge = uniswap.getTokenToEthOutputPrice(actualCharge);

        (tokenPrecharge);
        if (tokenPrecharge > tokenActualCharge) {
            //TODO: refund
            uniswaptoken.transfer(sender, tokenPrecharge - tokenActualCharge);
        } else {

        }
    }

}

contract KovanGsnMixer is GsnMixer {

    address constant hubAddr = 0xD216153c06E857cD7f72665E0aF1d7D82172F494;
    address constant cDaiUniswapExchange = 0x613639E23E91fd54d50eAfd6925AF2Ed6701A46b;

    constructor() GsnMixer(IUniswap(cDaiUniswapExchange), hubAddr) public {
    }
}

contract MainnetGsnMixer is GsnMixer {

  address constant hubAddr = 0xD216153c06E857cD7f72665E0aF1d7D82172F494;
  address constant cDaiUniswapExchange = 0x2a1530C4C41db0B0b2bB646CB5Eb1A67b7158667;

  constructor() GsnMixer(IUniswap(cDaiUniswapExchange), hubAddr) public {
  }
}


library str {
    function asd() internal returns (GsnMixer) {return new KovanGsnMixer();}
}
