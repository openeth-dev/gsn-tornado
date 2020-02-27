var _id=123456
function nextid() {
	return _id++
}

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

	//call the underlying "sendTransaction" of previous provider.
	origSendTransaction(options) {
		return this.origSend("eth_sendTransaction", [options])
	}

	//for any rpc "methodName", look of "this" object has such async method.
	// This class comes with "eth_sendTransaction" implementation
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

	//override this method to to alter actual transaction. 
	// make sure to call this "super.eth_sendTransaction" eventually..
	async eth_sendTransaction({from,to,gas,gasPrice,value,data}) {
		this.origSendTransaction({from,to,gas,gasPrice,value,data})
	}
}
