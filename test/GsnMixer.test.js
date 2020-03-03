/* global contract describe it assert */

const GsnMixer = artifacts.require('GsnMixer')
const LocalUniswap = artifacts.require('LocalUniswap')
const SampleToken = artifacts.require('SampleToken')
const DummyDeposit = artifacts.require('DummyDeposit')

//this require crashes: on: "Error: Cannot find module './lib/api'", so had to copy it in:
// const {  getRelayRequest } = require('@openeth/gsn/src/js/relayclient/utils')

const GasData = require('@openeth/gsn/src/js/relayclient/EIP712/GasData')
const RelayData = require('@openeth/gsn/src/js/relayclient/EIP712/RelayData')

function getRelayRequest (sender, recipient, txData, fee, gasPrice, gasLimit, senderNonce, relay, gasSponsor, baseFee) {
  return {
    target: recipient,
    encodedFunction: txData,
    gasData: new GasData({
      gasLimit: gasLimit.toString(),
      gasPrice: gasPrice.toString(),
      pctRelayFee: fee.toString(),
      baseRelayFee: baseFee ? baseFee.toString() : '0'// TODO: remove "?:"
    }),
    relayData: new RelayData({
      senderAccount: sender,
      senderNonce: senderNonce.toString(),
      relayAddress: relay,
      gasSponsor
    })
  }
}

// Traditional Truffle test
contract('GsnMixer', accounts => {
  let gm, uni, tok
  before(async () => {
    const hubaddr = '0x' + 'a'.repeat(40)
    uni = await LocalUniswap.new({ value: 1e18 })
    tok = await SampleToken.at(await uni.tokenAddress())
    gm = await GsnMixer.new(uni.address, hubaddr)
    await gm.setHub(accounts[0])
  })
  it('#splitSRV', async () => {
    const ss = '1'.repeat(64)
    const rr = '2'.repeat(64)
    const vv = '33'

    sig = '0x' + ss + rr + vv
    ret = await gm.contract.methods.splitRSV('0x' + rr + ss + vv).call()
    const { s, r, v } = ret
    assert.deepEqual({ s, r, v }, { s: '0x' + ss, r: '0x' + rr, v: parseInt(vv, 16).toString() })
  })

  async function callARC ({
                            sender = accounts[0],  //transaction sender
                            relay = '0x' + '1'.repeat(40),
                            from = '0x' + '2'.repeat(40),
                            encodedFunction,
                            transactionFee = '70',
                            gasPrice = 1e12,
                            gasLimit = 1e6,
                            nonce = 1,
                            approvalData = '0x',
                            maxPossibleGas

                          }) {

    const senderNonce = 0  // not tested by ARC anyway, only by RelayHub.
    const fee = 0 // %
    const baseFee = 0
    const req = getRelayRequest(from, /*recipient*/ gm.address, encodedFunction, fee, gasPrice, gasLimit, senderNonce, relay, /*sponsor*/ gm.address, baseFee)

    maxPossibleGas = 1e6
    // if ( !maxPossibleGas ) {
    //   try {
    //     maxPossibleGas = web3.eth.estimateGas({ from: sender, to: gm.address, data: encodedFunction })
    //   } catch (e) {
    //     //gas estimation failed..
    //     maxPossibleGas = 1e6
    //   }
    // }
    const ret = await gm.acceptRelayedCall.call(req, approvalData, maxPossibleGas, { from: sender })
    const code = ret[0].toNumber()
    const err = ret[1] ? Buffer.from(ret[1].replace(/^0x/, ''), 'hex').toString() : ''
    return { code, err }
  }

  describe('#acceptRelayedCall', async () => {
    let goodFunction, revertingFunction

    before( async()=>{
      //this function succeeds on chain
      goodFunction = gm.contract.methods.testFunction().encodeABI()

      //this function reverts on chain
      revertingFunction = gm.contract.methods.failFunction().encodeABI()
    })

    it.skip('can be called by hub only', async () => {
      try {
        await callARC({
          sender: accounts[1],
          encodedFunction: goodFunction
        })
      } catch (e) {
        assert.match(e, /revert Function can only be called by RelayHub/)
        return
      }
      assert.ok(false, 'should revert')
    })

    it('balance too low', async () => {
      const { code, err } = await callARC({
        encodedFunction: goodFunction
      })
      assert.deepEqual({ code, err }, { code: 101, err: 'DAI balance too low' })
    })

    it('revert on unsupported mixer', async () => {
      const dummyTornado = await DummyDeposit.new()
      const { code, err } = await callARC({
        encodedFunction: gm.contract.methods.deposit(dummyTornado.address, '0x', '0x').encodeABI()
      })
      assert.deepEqual({ code, err }, { code: 99, err: 'unsupported mixer' })
    })

    it('continue with a supported mixer', async () => {
      const { code, err } = await callARC({
        encodedFunction: gm.contract.methods.deposit('0xD4B88Df4D29F5CedD6857912842cff3b20C8Cfa3', '0x', '0x').
          encodeABI()
      })
      //it can't really succeed, since the address is correct, but its not really deployed.
      assert.deepEqual({ code, err }, { code: 99, err: '' })
    })

    it('ok', async () => {
      await tok.mint(1e18.toString(), { from: accounts[0] })
      const { code, err } = await callARC({
        from: accounts[0],
        encodedFunction: goodFunction
      })
      assert.equal( code==0 ? "ok" : code+ err , "ok" )
    })

    it('failed func', async () => {
      const { code, err } = await callARC({
        from: accounts[0],
        encodedFunction: revertingFunction
      })
      assert.deepEqual({ code, err }, { code: 99, err: 'failedFunc' })
    })

  })
})


