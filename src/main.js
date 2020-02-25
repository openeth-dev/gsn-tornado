/* global window */
const {WrapperProvider} = require( './wrapper-provider')
const GSN=require( '@openeth/gsn')
const Web3=require('Web3')
const IDAI = require( '../artifacts/IDAI.json')
const GsnMixer = require( '../artifacts/GsnMixer.json')


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

        data = mixer.methods.permit(token, holder, spender, nonce, expiry, allowed, sig)
            .encodeABI()

        return {
            to: window.mixer._address,
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
    window.ethereum = new WrapperProvider(window.ethereum, "wETH" )
    window.web3.currentProvider = new WrapperProvider(window.web3.currentProvider, "WEB3.cur" )
    // global.ethereum = WrapperProvider(global.ethereum, "gETH" )
    // global.web3 = WrapperProvider(global.web3, "gWEB3" )

    global.gsnRelayer = '0x9AE9FC73A7ad54004D7eEA2817787684FBE52433'
    global.gsnFee = "0x1234567890"

    window.mixer = new myWeb3.eth.Contract(GsnMixer.abi, gsnRelayer)

}

init()
