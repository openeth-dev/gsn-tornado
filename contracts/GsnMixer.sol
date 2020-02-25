pragma solidity ^0.5.4;

import "@0x/contracts-utils/contracts/src/LibBytes.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IDAI is IERC20 {
    function permit(address holder, address spender, uint256 nonce, uint256 expiry,
                bool allowed, uint8 v, bytes32 r, bytes32 s) external;
}

//the interface of the Tornado contract
// can't be a real interace, since "denomination" is a public member instead of view function
contract ITornado {
  uint256 public denomination;
  address public token; //from ERC20Tornado

  event Deposit(bytes32 indexed commitment, uint32 leafIndex, uint256 timestamp);
  event Withdrawal(address to, bytes32 nullifierHash, address indexed relayer, uint256 fee);


  /**
    @dev Deposit funds into the contract. The caller must send (for ETH) or approve (for ERC20) value equal to or `denomination` of this instance.
    @param _commitment the note commitment, which is PedersenHash(nullifier + secret)
  */
  function deposit(bytes32 _commitment) external payable;

  /**
    @dev Withdraw a deposit from the contract. `proof` is a zkSNARK proof data, and input is an array of circuit public inputs
    `input` array consists of:
      - merkle root of all deposits in the contract
      - hash of unique deposit nullifier to prevent double spends
      - the recipient of funds
      - optional fee that goes to the transaction sender (usually a relay)
  */
  function withdraw(bytes calldata _proof, bytes32 _root, bytes32 _nullifierHash, 
    address payable _recipient, address payable _relayer, uint256 _fee, uint256 _refund) external;

  /** @dev whether a note is already spent */
  function isSpent(bytes32 _nullifierHash) public view returns(bool);
}


//Wrapper contract for Tornado Mixer
// this way, we add GSN support for Tornado, whichout modifying the original contracts.
// It is simple for a mixer, since the mixer itself doesn't really care about the msg.sender
// (that's almost true: it assumes it has Approval to withdraw tokens from it. This means all deposits
// go through the GsnMixer)
// variable - a GSN-aware contract has to use a helper method getSender() instead of msg.sender.
contract GsnMixer {

    //relaying withdraw fee in tokens (1 DAI)
    // (taken out of the deposited value)
    uint public withdrawFee = 1 ether;

    constructor() public {

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

    //placeholder for GSN.
    function getSender() view internal returns(address) {
        return msg.sender;
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

    function permit(IDAI token, address holder, address spender, uint256 nonce, uint256 expiry,
                    bool allowed, bytes calldata sig) external {

        approveOwner(token);

        ( bytes32 r, bytes32 s, uint8 v )  = splitRSV(sig);
        if ( nonce == 0 ) 
          nonce = token.nonces(holder);

        (bool success, bytes memory ret ) = address(token).call(abi.encodeWithSelector(token.permit.selector,
          holder, spender, nonce, expiry, allowed, v,r,s
          ));
        emit Permit(success, getError(ret) );
    }
    event Permit(bool success, string err);

    function getError(bytes memory err) internal pure returns (string memory ret) {
      if ( err.length < 4+32 )
        return string(err);
      (ret) = abi.decode(LibBytes.slice(err,4,err.length), (string));
    }

    //we got the DAI deposit from the client. so forward it, after giving the mixer allowance
    function deposit(ITornado mixer, bytes32 _id) external {
        IERC20 token = IERC20(mixer.token());
        approveOwner(token);
        token.transferFrom( getSender(), address(this), mixer.denomination()+withdrawFee);
        //allow the mixer to pull the tokens from us..
        if ( token.allowance(address(this), address(mixer)) ==0 ) {
            token.approve(address(mixer), uint(-1));
        }
        mixer.deposit(_id);
    }
    //function withdraw(bytes _proof, bytes32 _root, bytes32 _nullifierHash, address _recipient, address _relayer, uint256 _fee, uint256 _refund) 
}
