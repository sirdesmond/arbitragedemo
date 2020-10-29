let Flashloan = artifacts.require("Flashloan")

module.exports = async function (deployer, network) {
    try {

        let lendingPoolAddressesProviderAddress;
        let uniswapV2Router;
        let kyberProxy;
        let contractRegistry;

        switch(network) {
            case "mainnet":
            case "mainnet-fork":
            case "development": // For Ganache mainnet forks
                lendingPoolAddressesProviderAddress = "0x24a42fD28C976A61Df5D00D0599C34c4f90748c8"; 
                uniswapV2Router = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
                kyberProxy = "0x818E6FECD516Ecc3849DAf6845e3EC868087B755"
                contractRegistry = "0xA6DB4B0963C37Bc959CbC0a874B5bDDf2250f26F";

                break
            case "ropsten":
            case "ropsten-fork":
                lendingPoolAddressesProviderAddress = "0x1c8756FD2B28e9426CDBDcC7E3c4d64fa9A54728";
                uniswapV2Router = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
                kyberProxy = "0x818E6FECD516Ecc3849DAf6845e3EC868087B755";
                contractRegistry = "0xA6DB4B0963C37Bc959CbC0a874B5bDDf2250f26F";
                break
            case "kovan":
            case "kovan-fork":
                lendingPoolAddressesProviderAddress = "0x506B0B2CF20FAA8f38a4E2B524EE43e1f4458Cc5";
                uniswapV2Router = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
                kyberProxy = "0x818E6FECD516Ecc3849DAf6845e3EC868087B755" 
                contractRegistry = "0xA6DB4B0963C37Bc959CbC0a874B5bDDf2250f26F";
                break
            default:
                throw Error(`Are you deploying to the correct network? (network selected: ${network})`)
        }

        await deployer.deploy(Flashloan, lendingPoolAddressesProviderAddress, uniswapV2Router, kyberProxy, contractRegistry)
    } catch (e) {
        console.log(`Error in migration: ${e.message}`)
    }
}