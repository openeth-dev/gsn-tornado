pragma solidity ^0.5.4;

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
