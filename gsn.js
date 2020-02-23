function wraplog(obj, title="") {
	function sendAsync(options,cb) {
		console.log( "====",title,"sendAsync", options )
		origAsync=this
		origAsync(options, (err,res)=>{
			console.log( "====",title, "sendAsync ret", err||res)
			cb(err,res)
		})
	}
	return new Proxy(obj, {
		get: (obj,attr) => {
			if ( attr ==='sendAsync' ) {
				sa = obj.sendAsync
				if ( !sa )
					return sendAsync
				return sendAsync.bind(sa.bind(obj))
			}
			console.log( "===" ,title, "get:", attr )
			return obj[attr];
		},
		set: (obj,attr,value) => {
			console.log( "===", title, "set:", attr, "=", value )
			obj[attr]=value
			return true
		}
	})
}

console.log( "== GSN ==" )

if ( typeof window != 'undefined' ) {
	window.web3.currentProvider = wraplog(window.web3, "web3.curProv" )
	window.ethereum = wraplog(window.ethereum, "ETH" )
	window.web3 = wraplog(window.web3, "WEB3" )
}



