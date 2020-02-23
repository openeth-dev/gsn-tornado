
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
	async eth_sendTransaction({from,to,gas,gasPrice,value,data}) {
		console.log( "sendTX", {from,to,data})
		return this.origSend("eth_sendTransaction", [{from,to,gas,gasPrice,value,data}] )
	}
}