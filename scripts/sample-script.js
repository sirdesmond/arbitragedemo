// We require the Hardhat Runtime Environment explicitly here. This is optional 
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile 
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  let lendingPoolAddressesProviderAddress;
  let uniswapV2Router;
  let kyberProxy;
  let contractRegistry;

  lendingPoolAddressesProviderAddress =
  "0x1c8756FD2B28e9426CDBDcC7E3c4d64fa9A54728";
uniswapV2Router = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
kyberProxy = "0x818E6FECD516Ecc3849DAf6845e3EC868087B755";
contractRegistry = "0xA6DB4B0963C37Bc959CbC0a874B5bDDf2250f26F";

  const Flashloan = await hre.ethers.getContractFactory("Flashloan");

  const flasher = await Flashloan.deploy(
    lendingPoolAddressesProviderAddress,
    uniswapV2Router,
    kyberProxy,
    contractRegistry
  );

  await flasher.deployed();

  console.log("Flasher deployed to:", flasher.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
