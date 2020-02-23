// This script uses @nomiclabs/buidler-truffle5
const GsnMixer = artifacts.require("GsnMixer");

async function main() {
  const mixer = await GsnMixer.new();

  console.log("GsnMixer address:", mixer.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
