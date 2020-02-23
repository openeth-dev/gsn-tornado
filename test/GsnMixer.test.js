const GsnMixer = artifacts.require("GsnMixer");

// Traditional Truffle test
contract("GsnMixer", accounts => {
	let gm
	before( async() => {
		gm = await GsnMixer.new()
	})
	it( "#splitSRV", async() => {
		const ss = "1".repeat(64)
		const rr = "2".repeat(64)
		const vv = "33"

		 sig="0x"+ss+rr+vv
		ret=await gm.contract.methods.splitSRV("0x"+ ss+rr+vv ).call()
		const {s,r,v} = ret 
		assert.deepEqual({s,r,v}, {s:"0x"+ss, r:"0x"+rr, v:parseInt(vv,16).toString()} )
	})
});


