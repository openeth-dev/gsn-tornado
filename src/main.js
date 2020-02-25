/* global window */
const {WrapperProvider} = require( './wrapper-provider')
const GSN=require( '@openeth/gsn')
const Web3=require('web3')
const IDAI = require( '../artifacts/IDAI.json')
const GsnMixer = require( '../artifacts/GsnMixer.json')
const abi = require( 'web3-eth-abi')

const verbose=true

const approveSig = "0x095ea7b3"   //ERC20.approve(address,uint256)

const depositSig = abi.encodeFunctionSignature('deposit(bytes32)')

const   permitSig = abi.encodeFunctionSignature("permit(address,address,address,uint256,uint256,bool,bytes)")
// const withdrawSig = '0x21a0adb632'
const withdrawSig = abi.encodeFunctionSignature("withdraw(bytes,bytes32,bytes32,address,address,uint256,uint256)")

//same sig, just added "address" as first param
const gsnMixerWithdrawSig = 
                    abi.encodeFunctionSignature("withdraw(address,bytes,bytes32,bytes32,address,address,uint256,uint256)")
//nonce(address)
const nonceSig = '0x70ae92d2'


class MixerProvider extends WrapperProvider {

    constructor( origProvider ) {
        let provider = origProvider

        let relayprovider = new GSN.RelayProvider(origProvider, {verbose, force_gasLimit:2e6})
        let useGSN=true
        if ( useGSN ) {
            //a provider that pass-through any method that is not defined in RelayProvider
            // (e.g. event handling)
            const wrapper = new Proxy( origProvider, {
                 get:(target,prop)=>{ 
                    console.log('prop=',prop)
                    //TODO: RelayProvider's "enable" is broken... 
                    if ( prop==='enable' ) return origProvider.enable
                    return relayprovider[prop] || target[prop] 
                }
             })
            provider = wrapper
        }

        super(provider)
    }

    async eth_sendTransaction({from,to,gas,gasPrice,value,data}) {
        console.log( " ", {from,to,data})
        // return this.origSend("eth_sendTransaction", [{from,to,gas,gasPrice,value,data}] )
        if ( data.startsWith(depositSig)) {
            console.log( '=== proxy deposit')
            // convert: tornado.deposit(commitment)
            // to:      gsnmixer(tornado,commitment, permitSig)
            const commitment = abi.decodeParameters(['bytes32'], data.slice(10))[0]
            let permitUserSig = '0x'
            if ( await dai.methods.allowance(from, window.gsnmixer._address).call() === '0' ) {
                console.log( "no allowance for GsnMixer. ask user to sign")
                const sig  = await signpermit({from,holder:from,spender:window.gsnmixer._address});
                permitUserSig = sig.sig
                //user gave allowance to the Tornado, but not to our proxy... need to add one
            }


            data = window.gsnmixer.methods.deposit(to, commitment, permitUserSig).encodeABI()
            to = window.gsnmixer._address

        } else if ( data.startsWith(approveSig)) {
            //convert token.approve(spender,amount)
            //to:   gsnmixer.permit(token, from, spender, true, {sig} )
            // NOTE: pops-up a UI for signTypedData

            //we don't really care the amount of original "approve", as "permit only gets a true/false boolean..
            const spender_amount = abi.decodeParameters(['address','uint256'], data.slice(10))
            let spender = spender_amount[0];

            //TODO: who should we approve? the UI asks for the Tornado to be approved. but we
            // need to approve our GsnMixer, which in turn will approve tornado
            //spender = mixer._address
            const ret  = await createDaiPermitTransaction({from, holder:from, token:to, spender})
            data = ret.data
            to = ret.to
            gas = 1e6.toString()
        } else 
        if ( data.startsWith(withdrawSig)) {
            //convert mixer.withdraw(...)
            //to:     gsnmixer.withdraw(mixer, ...)
            // withdraw(bytes,bytes32,bytes32,address,address,uint256,uint256) external {
            const params = abi.decodeParameters(
                    ['bytes','bytes32','bytes32','address','address','uint256','uint256'], 
                    data.slice(10))

            delete params.__length__
            console.log( "decoded params=",params)
            data = window.gsnmixer.methods.withdraw( to, ...Object.values(params) ).encodeABI()

            to = window.gsnmixer._address
            console.log( "==== through GSN mixer")
        }
        return this.origSendTransaction({from,to,gas,gasPrice,value,data} )
    }
}

var chainId
async function signpermit({from,holder,spender,expiry=0, allowed=true}) {

    if ( !chainId) {
         chainId = await myWeb3.eth.net.getId()
         console.log( "chainId=",chainId)
    }   

    //based on: https://github.com/mosendo/gasless/blob/7688283021bbdb1c99b6951944345af0ba06e036/app/src/utils/relayer.js#L38-L79
    const Permit = [
        { name: "holder", type: "address" },
        { name: "spender", type: "address" },
        { name: "nonce", type: "uint256" },
        { name: "expiry", type: "uint256" },
        { name: "allowed", type: "bool" }
    ];
    const EIP712Domain = [
        { name: "name", type: "string" },
        { name: "version", type: "string" },
        { name: "chainId", type: "uint256" },
        { name: "verifyingContract", type: "address" },
    ];
    const domain = {
        name: "Dai Stablecoin",
        version: "1",
        chainId,
        verifyingContract: dai._address
    };

    const nonce = await dai.methods.nonces(holder).call()

    var message = {
        holder,
        spender,
        nonce,
        expiry: expiry.toString(),
        allowed
    };

    const data = JSON.stringify({
        types: {
            EIP712Domain,
            Permit
        },
        domain,
        primaryType: "Permit",
        message
    });

    const sig = await new Promise((resolve,reject)=>web3.currentProvider.sendAsync({
        method: "eth_signTypedData_v3",
        params: [from, data],
        from
    }, (err,res) => {
        if (err)reject(err.error||err)
        else resolve(res.result)
    }))

    return { ...message, sig}
}

//create a "permit" transaction, to be sent with sendTransaction to our mixer
// returns { data,to } values for sendTransaction
window.createDaiPermitTransaction = async function({from, holder, token, spender, allowed=true}) {
        // function permit(address holder, address spender, uint256 nonce, 
        //   uint256 expiry, bool allowed, uint8 v, bytes32 r, bytes32 s) 

        //just validation: we currently support only "permit" of DAI
        if ( token && token != dai._address )
            throw Error( `invalid DAI address ${token} should be: ${dai._address}`)

        if ( !/^0x/.test(holder)) {
            throw Error( 'invalid "holder" address: '+holder)
        }
        if ( !/^0x/.test(spender)) {
            throw Error( 'invalid "spender" address: '+spender)
        }
        if ( allowed !== true && allowed != false ) {
            throw Error( 'invalid "allowed" bool: '+allowed)
        }
        
        console.log( "before permit allowance=", await dai.methods.allowance(holder, spender)
            .call())
        const ret = await signpermit({from, spender, holder, allowed})
        const {
            nonce,
            expiry,
            sig
        }  = ret

        // r = sig.slice(0,66)
        // s = '0x'+sig.slice(66,66+64)
        // v = '0x'+sig.slice(66+64)
        // const { r,s,v } = await mixer.methods.splitRSV(sig).call()

        // dai.methods.permit(
        //         holder, spender, nonce, expiry, allowed, v,r,s
        //     ).send({from:sender})

        // function permit(IDAI token, address holder, address spender, uint256 nonce, 
        //     uint256 expiry, bool allowed, bytes calldata sig) 

        data = window.gsnmixer.methods.permit(token, holder, spender, nonce, expiry, allowed, sig)
            .encodeABI()

        return {
            to: window.gsnmixer._address,
            data
        }
}


function init() {
    if ( global.gsninitialized )
        return 

    window.myWeb3 = new Web3(window.ethereum)

    window.dai = new myWeb3.eth.Contract(IDAI.abi, '0x4f96fe3b7a6cf9725f59d353f723c1bdb64ca6aa')
    console.log( "=== GSN webpacked ===" )
    global.gsninitialized=true

    // window.web3.currentProvider = WrapperProvider(window.web3.currentProvider, "web3.curProv" )
    //TODO: do we need both ?
    window.ethereum = new MixerProvider(window.ethereum, "wETH" )
    window.web3.currentProvider = new MixerProvider(window.web3.currentProvider, "WEB3.cur" )

    // global.ethereum = WrapperProvider(global.ethereum, "gETH" )
    // global.web3 = WrapperProvider(global.web3, "gWEB3" )

    // global.gsnRelayer = '0x0f65a641879cCeB87164420eafc0096623a995f1' //reverts on withdraw, on send to caller.
    global.gsnRelayer = '0x2ADAf67C67f62B034FEeb62836E85fb4666dbE4b'
    global.gsnFee = '0x'+1e18.toString(16)

    window.gsnmixer = new myWeb3.eth.Contract(GsnMixer.abi, gsnRelayer)

}

init()
