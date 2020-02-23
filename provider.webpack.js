const path = require('path')
// BundleAnalyzerPlugin = require('webpack-bundle-analyzer').BundleAnalyzerPlugin

module.exports = {
  plugins: [
    //      new BundleAnalyzerPlugin()
  ],

  entry: './src/main.js',
  mode: 'development',
  output: {
    path: path.resolve(__dirname, 'site'),
    filename: 'gsn.js'
  }
}
