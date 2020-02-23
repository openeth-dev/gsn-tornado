/* global window */
const {WrapperProvider} = require( './wrapper-provider')
const GSN=require( '@openeth/gsn')


function init() {
    if ( global.gsninitialized )
        return 

    console.log( "=== GSN webpacked ===" )
    global.gsninitialized=true

    // window.web3.currentProvider = WrapperProvider(window.web3.currentProvider, "web3.curProv" )
    window.ethereum = new WrapperProvider(window.ethereum, "wETH" )
    window.web3.currentProvider = new WrapperProvider(window.web3.currentProvider, "WEB3.cur" )
    // global.ethereum = WrapperProvider(global.ethereum, "gETH" )
    // global.web3 = WrapperProvider(global.web3, "gWEB3" )

    global.gsnRelayer = "0x7149173Ed76363649675C3D0684cd4Bac5A1006d"
    global.gsnFee = "0x1234567890"

}

init()