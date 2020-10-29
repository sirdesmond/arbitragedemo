const { expect } = require("chai");

describe("Flashloan", function () {
  let lendingPoolAddressesProviderAddress;
  let uniswapV2Router;
  let kyberProxy;
  let contractRegistry;
  let flasher;

  beforeEach(async function() {
    const Flashloan = await ethers.getContractFactory("Flashloan");

    lendingPoolAddressesProviderAddress =
      "0x1c8756FD2B28e9426CDBDcC7E3c4d64fa9A54728";
    uniswapV2Router = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
    kyberProxy = "0x818E6FECD516Ecc3849DAf6845e3EC868087B755";
    contractRegistry = "0xA6DB4B0963C37Bc959CbC0a874B5bDDf2250f26F";

    flasher = await Flashloan.deploy(
      lendingPoolAddressesProviderAddress,
      uniswapV2Router,
      kyberProxy,
      contractRegistry
    );

    await flasher.deployed();

  });

  it("Should request flash loan successfully", async function () {

    console.log("Flasher deployed to:", flasher.address);
    const result = await flasher.flashloan('0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE','100000000000000000','0xf80A32A835F79D7787E8a8ee5721D0fEaFd78108','100000000000000000',1);
    console.log('the result of arb: ', result)
  });
});
