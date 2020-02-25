const abi = require( 'web3-eth-abi')
var _id=123456
function nextid() {
	return _id++
}

const	approveSig = "0x095ea7b3"

const 	permitSig = abi.encodeFunctionSignature("permit(address,address,address,uint256,uint256,bool,bytes)")

//nonce(address)
const nonceSig = '0x70ae92d2'

export class WrapperProvider {
	constructor(provider, title="") {
		if ( !provider.send )
			throw Error( "no 'send'")
		this.provider=provider
		this.title=title
	}

	enable() {
		return this.provider.enable(arguments)
	}

	origSend(method, params, {id,jsonrpc="2.0"}= {}) {
		return new Promise((resolve,reject)=> {
			this.provider.sendAsync({method,params,id: id || nextid(), jsonrpc}, (err,res)=>{
				if (err) { 
					reject(err.error || err)
				}
				resolve(res.result)
			})
		})
	}

	origSendTransaction(options) {
		return this.origSend("eth_sendTransaction", [options])
	}


	sendAsync(options,cb) {
		console.log("===>> ",this.title, options.method, options.params, options.params.id, options.params.jsonrpc)
		const callback = (err,res)=>{
			console.log("===",this.title, options.method, "err=", err, "ret=" ,res)
			cb(err,res)
		}

		if ( typeof this[options.method] === 'function' ) {
			const { id, jsonrpc, params } = options
			this[options.method].apply(this, params)
				.then( result=>callback(null, { id, jsonrpc, result }))
				.catch(error =>callback(null, { id, jsonrpc, error }))
			return
		}

		this.provider.sendAsync(options,callback)
	}

//	    function permit(IDAI token, address holder, address spender, 
				// uint256 nonce, uint256 expiry,
//                    bool allowed, bytes calldata sig) external {

	async eth_sendTransaction({from,to,gas,gasPrice,value,data}) {
		console.log( "sendTX", {from,to,data})
		return this.origSend("eth_sendTransaction", [{from,to,gas,gasPrice,value,data}] )
		if ( data.startsWith(approveSig)) {
			//convert token.approve(spender,amount)
			//to: 	gsnmixer.permit(token, from, spender, true, {sig} )
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
		}
		return this.origSendTransaction({from,to,gas,gasPrice,value,data} )
	}
}