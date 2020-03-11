pragma solidity ^0.5.4;
pragma experimental ABIEncoderV2;

import "@0x/contracts-utils/contracts/src/LibBytes.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "@openeth/gsn/contracts/BaseRelayRecipient.sol";
import "@openeth/gsn/contracts/utils/GsnUtils.sol";
import "@openeth/gsn/contracts/samples/DryRunSponsor.sol";
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

contract GsnMixer is DryRunSponsor  {

    mapping(address => bool) public validMixers;
    //relaying withdraw fee in tokens (1 DAI)
    // (taken out of the deposited value)
    uint public withdrawFeeDai = 1 ether;
    uint public depositFeeDai = 1 ether;
    IUniswap uniswap;
    IERC20 uniswaptoken;

    uint postGas;


    //TODO: Currently can't implement both Sponsor and Recipient.
    //copy Recipient's getSender, since we can't simply inherit both
    // GsnRecipient and GsnSponsor (causes duplicate "relayHub" member)
    function getSender() public view returns (address) {
        if (msg.sender == address(relayHub)) {
            // At this point we know that the sender is a trusted IRelayHub,
            // so we trust that the last bytes of msg.data are the verified sender address.
            // extract sender address from the end of msg.data
            return LibBytes.readAddress(msg.data, msg.data.length - 20);
        }
        return msg.sender;
    }

    // Gas stipends for acceptRelayedCall, preRelayedCall and postRelayedCall
    uint256 constant private ACCEPT_RELAYED_CALL_MAX_GAS = 500_000; //enough to cover verifyProof
    uint256 constant private PRE_RELAYED_CALL_MAX_GAS = 100000;
    uint256 constant private POST_RELAYED_CALL_MAX_GAS = 110000;

    function getGasLimitsForSponsorCalls()
    external
    view
    returns (
        GSNTypes.SponsorLimits memory limits
    ) {
        return GSNTypes.SponsorLimits(
            ACCEPT_RELAYED_CALL_MAX_GAS,
            PRE_RELAYED_CALL_MAX_GAS,
            POST_RELAYED_CALL_MAX_GAS
        );
    }

    bool testAnyMethod;

    constructor(IUniswap _uniswap, IRelayHub hub, bool _testAnyMethod ) DryRunSponsor(hub) public {
        uniswap = _uniswap;
        uniswaptoken = IERC20(uniswap.tokenAddress());
        testAnyMethod = _testAnyMethod;

        //we're the only valid recipient for dryrun
        addRecipient(address(this), true);

        //all trusted mixer instances, on Kovan and Mainnet
        validMixers[0xD4B88Df4D29F5CedD6857912842cff3b20C8Cfa3] = true;
        validMixers[0xFD8610d20aA15b7B2E3Be39B396a1bC3516c7144] = true;
        validMixers[0xF60dD140cFf0706bAE9Cd734Ac3ae76AD9eBC32A] = true;
        validMixers[0xdf2d3cC5F361CF95b3f62c4bB66deFe3FDE47e3D] = true;
        validMixers[0xD96291dFa35d180a71964D0894a1Ae54247C4ccD] = true;
        validMixers[0xb192794f72EA45e33C3DF6fe212B9c18f6F45AE3] = true;

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
        return relayHub.balanceOf(address(this));
    }

    /// withdraw deposit from relayHub
    function withdrawRelayHubDepositTo(uint amount, address payable target) public onlyOwner {
        relayHub.withdraw(amount, target);
    }

    function relayHubDeposit() public payable onlyOwner {
        relayHub.depositFor.value(msg.value)(address(this));
    }

    function failFunction() pure external {
        revert("failedFunc");
    }

    function testFunction() pure external {
    }

    //"internal"
    function splitRSV(bytes memory sig) pure public
    returns (bytes32 r, bytes32 s, uint8 v) {

        bytes1 b1;
        require(sig.length >= 65, "invalid sig");
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
        require(success, getError(ret));
    }

    //we got the DAI deposit from the client. so forward it, after giving the mixer allowance
    function deposit(ITornado tornado, bytes32 _id, bytes calldata permitSig) external {

        require(validMixers[address(tornado)], "deposit: unsupported mixer");
        address sender = getSender();
        IDAI token = IDAI(tornado.token());
        if (permitSig.length > 0) {
            //we don't have to check it: if the "permit" fails for any reason,
            // the "deposit" will revert
            this.permit(token, sender, address(this), token.nonces(sender), 0, true, permitSig);
        }

        approveOwner(token);

        token.transferFrom(sender, address(this), tornado.denomination() + depositFeeDai);
        //allow the mixer to pull the tokens from us..
        if (token.allowance(address(this), address(tornado)) == 0) {
            token.approve(address(tornado), uint(- 1));
        }
        tornado.deposit(_id);
    }

    function withdraw(ITornado tornado, bytes calldata _proof, bytes32 _root, bytes32 _nullifierHash,
        address payable _recipient, address payable _relayer, uint256 _fee, uint256 _refund) external {

        require( validMixers[address(tornado)], "withdraw: unsupported mixer" );
        require(_relayer == address(this), "withdraw: wrong 'relayer'");
        require(_fee >= withdrawFeeDai, "withdraw: fee too low");

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

        if (relayRequest.target != address(this)) {
            return (100, "target must be gsnMixer");
        }

        if ( !testAnyMethod ) {
            bytes4 sel = LibBytes.readBytes4(relayRequest.encodedFunction, 0);
            if ( sel != this.withdraw.selector && sel != this.deposit.selector && sel != this.permit.selector ) {
                return ( 102, "wrong method");
            }
        }

        address from = relayRequest.relayData.senderAccount;
        {
            //we require method to be executable without revert
            (bool success, string memory ret) = relayHub.dryRun(
                from,
                relayRequest.target,
                relayRequest.encodedFunction,
                relayRequest.gasData.gasLimit);

            if (!success)
                return (99, bytes(ret));
        }

        //instead of "generic" pricing, our methods (deposit/withdraw) perform
        // their fee, instead of pre/post calls.
//        uint maxPossibleCharge = getRelayHub().calculateCharge(maxPossibleGas, relayRequest.gasData.gasPrice, relayRequest.gasData.pctRelayFee);
//        uint tokenPrecharge = uniswap.getTokenToEthOutputPrice(maxPossibleCharge);
       return (0,"");
    }

    //TODO: genericTokenSponsor can handle precharge/refunds.

}

contract KovanGsnMixer is GsnMixer {

    address constant hubAddr = 0xD216153c06E857cD7f72665E0aF1d7D82172F494;
    address constant cDaiUniswapExchange = 0x613639E23E91fd54d50eAfd6925AF2Ed6701A46b;

    constructor() GsnMixer(IUniswap(cDaiUniswapExchange), IRelayHub(hubAddr), false) public {
    }
}

contract MainnetGsnMixer is GsnMixer {

    address constant hubAddr = 0xD216153c06E857cD7f72665E0aF1d7D82172F494;
    address constant cDaiUniswapExchange = 0x2a1530C4C41db0B0b2bB646CB5Eb1A67b7158667;

    constructor() GsnMixer(IUniswap(cDaiUniswapExchange), IRelayHub(hubAddr), false) public {
    }
}


library str {
    function asd() internal returns (GsnMixer) {return new KovanGsnMixer();}
}
