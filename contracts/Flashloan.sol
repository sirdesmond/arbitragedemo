//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;

import "./aave/FlashLoanReceiverBase.sol";
import "./aave/ILendingPoolAddressesProvider.sol";
import "./aave/ILendingPool.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@nomiclabs/buidler/console.sol";

/**
    Ropsten instances:
    - Uniswap V2 Router:                    0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    - Sushiswap V1 Router:                  No official sushi routers on testnet
    - DAI:                                  0xf80A32A835F79D7787E8a8ee5721D0fEaFd78108
    - ETH:                                  0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    - Aave LendingPoolAddressesProvider:    0x1c8756FD2B28e9426CDBDcC7E3c4d64fa9A54728
    - kyber network proxy:                  0x818E6FECD516Ecc3849DAf6845e3EC868087B755
    - Contract Registry: Bancor             0xFD95E724962fCfC269010A0c6700Aa09D5de3074
    - Contract Registry : Bancor 2          0xA6DB4B0963C37Bc959CbC0a874B5bDDf2250f26F
   
    Mainnet instances:
    - Uniswap V2 Router:                    0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    - Sushiswap V1 Router:                  0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
    - DAI:                                  0x6B175474E89094C44Da98b954EedeAC495271d0F
    - ETH:                                  0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    - Aave LendingPoolAddressesProvider:    0x24a42fD28C976A61Df5D00D0599C34c4f90748c8
    - Bancor : Contract Registry            0x52Ae12ABe5D8BD778BD5397F99cA900624CfADD4
*/


interface IERC20Token {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address _owner) external view returns (uint256);
    function allowance(address _owner, address _spender) external view returns (uint256);

    function transfer(address _to, uint256 _value) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool);
    function approve(address _spender, uint256 _value) external returns (bool);
}


/// @title Kyber Network interface
interface IKyberNetworkProxy {
    event ExecuteTrade(
        address indexed trader,
        ERC20 src,
        ERC20 dest,
        address destAddress,
        uint256 actualSrcAmount,
        uint256 actualDestAmount,
        address platformWallet,
        uint256 platformFeeBps
    );

    /// @notice backward compatible
    function tradeWithHint(
        ERC20 src,
        uint256 srcAmount,
        ERC20 dest,
        address payable destAddress,
        uint256 maxDestAmount,
        uint256 minConversionRate,
        address payable walletId,
        bytes calldata hint
    ) external payable returns (uint256);

    function tradeWithHintAndFee(
        ERC20 src,
        uint256 srcAmount,
        ERC20 dest,
        address payable destAddress,
        uint256 maxDestAmount,
        uint256 minConversionRate,
        address payable platformWallet,
        uint256 platformFeeBps,
        bytes calldata hint
    ) external payable returns (uint256 destAmount);

    function trade(
        ERC20 src,
        uint256 srcAmount,
        ERC20 dest,
        address payable destAddress,
        uint256 maxDestAmount,
        uint256 minConversionRate,
        address payable platformWallet
    ) external payable returns (uint256);

    /// @notice backward compatible
    /// @notice Rate units (10 ** 18) => destQty (twei) / srcQty (twei) * 10 ** 18
    function getExpectedRate(
        ERC20 src,
        ERC20 dest,
        uint256 srcQty
    ) external view returns (uint256 expectedRate, uint256 worstRate);

    function getExpectedRateAfterFee(
        ERC20 src,
        ERC20 dest,
        uint256 srcQty,
        uint256 platformFeeBps,
        bytes calldata hint
    ) external view returns (uint256 expectedRate);
}

interface IBancorNetwork {
    function convertByPath(
        address[] memory _path, 
        uint256 _amount, 
        uint256 _minReturn, 
        address _beneficiary, 
        address _affiliateAccount, 
        uint256 _affiliateFee
    ) external payable returns (uint256);

    function rateByPath(
        address[] memory _path, 
        uint256 _amount
    ) external view returns (uint256);

    function conversionPath(
        address _sourceToken, 
        address _targetToken
    ) external view returns (address[] memory);
}

interface IContractRegistry {
    function addressOf(
        bytes32 contractName
    ) external returns(address);
}


contract Flashloan is FlashLoanReceiverBase {
    using SafeMath for uint256;
    IUniswapV2Router02 uniswapV2Router;
    IUniswapV2Router02 sushiswapV1Router;
    IKyberNetworkProxy kyberProxy;
    IContractRegistry contractRegistry;
    uint256 deadline;
    IERC20Token dai;
    address daiTokenAddress;
    uint256 amountToTrade;
    uint256 tokensOut;
    uint256 public platformFeeBps;
    bytes PERM_HINT = "PERM";
    address returnAddress;
    bytes32 bancorNetworkName = '0x42616e636f724e6574776f726b';
    IBancorNetwork bancorNetwork;

    event BancorFailed(string indexed idxReason, string reason);

    event BancorSwap(string indexed idxMsg, string msg);



    /**
        Initialize deployment parameters
     */
    constructor(
        address _aaveLendingPool,
        IUniswapV2Router02 _uniswapV2Router,
        IKyberNetworkProxy _kyberProxy,
        IContractRegistry _contractRegistry
    ) public FlashLoanReceiverBase(_aaveLendingPool) {
        // instantiate SushiswapV1 and UniswapV2 Router02
        uniswapV2Router = IUniswapV2Router02(address(_uniswapV2Router));
        kyberProxy = IKyberNetworkProxy(address(_kyberProxy));
        contractRegistry = IContractRegistry(_contractRegistry);
        console.log('Deploying a flasher...');
        // setting deadline to avoid scenario where miners hang onto it and execute at a more profitable time
        // deadline = block.timestamp + 300; // 5 minutes
    }

    //how the function recieves ether
    fallback() external payable {}

    /**
        This function is called after your contract has received the flash loaned amount
     */
    function executeOperation(
        address _reserve,
        uint256 _amount,
        uint256 _fee,
        bytes calldata _params
    ) external override {
        IERC20Token theToken = IERC20Token(_reserve);

        // uint256 thisContractBalanceNow = theToken.balanceOf(address(this));
        // uint256 userBalance = theToken.balanceOf(returnAddress);

        // uint256 userPlusContract = userBalance + thisContractBalanceNow;

        // uint256 amountAndFee = (_amount + _fee);
        // // require(
        //     thisContractBalanceNow < amountAndFee ||
        //         userPlusContract < amountAndFee,
        //     "The transaction did not return a profit + fee. Amount returned was not enough "
        // );

        // if (thisContractBalanceNow < amountAndFee) {
        //     uint256 difference = amountAndFee - thisContractBalanceNow;
        //     require(
        //         theToken.transferFrom(returnAddress, address(this), difference),
        //         "You dont have a high enough balance or appropriate approvals to do this transaction to cover your loan."
        //     );
        // }
        //
        // Your logic goes here.
        // !! Ensure that *this contract* has enough of `_reserve` funds to payback the `_fee` !!
        //

        // execute arbitrage strategy
        try this.executeArbitrage()  {} catch Error(string memory) {
            // Reverted with a reason string provided
        } catch (bytes memory) {
            // failing assertion, division by zero.. blah blah
        }

        uint256 totalDebt = _amount.add(_fee);
        transferFundsBackToPoolInternal(_reserve, totalDebt);
    }

    /**
        The specific cross protocol swaps that makes up your arb strategy
        UniswapV2 -> SushiswapV1 example below
     */
    function executeArbitrage() public {
        // Trade 1: Execute swap of Ether into designated ERC20 token on UniswapV2
        deadline = block.timestamp + 300; // 5 minutes

        console.log('running trade 1 on uniswap...');
        try
            uniswapV2Router.swapETHForExactTokens{value: amountToTrade}(
                amountToTrade,
                getPathForETHToToken(daiTokenAddress),
                address(this),
                deadline
            )
        {}  catch Error(string memory error) {
           console.log('error running uni swap transaction', error);
        }

        // Re-checking prior to execution since the NodeJS bot that instantiated this contract would have checked already
        uint256 tokenAmountInWEI = tokensOut.mul(1000000000000000000); //convert into Wei
        // uint256 estimatedETH = getEstimatedETHForToken(
        //     tokensOut,
        //     daiTokenAddress
        // )[0]; // check how much ETH you'll get for x number of ERC20 token

        // grant uniswap / kyber access to your token, DAI used since we're swapping DAI back into ETH
        dai.approve(address(uniswapV2Router), tokenAmountInWEI);

        // dai.approve(address(kyberProxy), tokenAmountInWEI);
        // dai.approve(address(bancorNetwork), tokenAmountInWEI);


        // Trade 2: Execute swap of the ERC20 token back into ETH on bancor to complete the arb
        console.log('running trade 2 on bancor...');

        try this.bancorSwap(
            daiTokenAddress, 
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE), 
            tokensOut
            )
        {}  catch Error(string memory error) {
           console.log('error running bancor swap', error) ;
        }

    }

    /**
        sweep entire balance on the arb contract back to contract owner
     */
    function WithdrawBalance() public payable onlyOwner {
        // withdraw all ETH
        msg.sender.call{value: address(this).balance}("");

        // withdraw all x ERC20 tokens
        dai.transfer(msg.sender, dai.balanceOf(address(this)));
    }

    function sendEther() public onlyOwner {

    }

    /**
        Flash loan x amount of wei's worth of `_flashAsset`
        e.g. 1 ether = 1000000000000000000 wei
     */
    function flashloan(
        address _flashAsset,
        uint256 _flashAmount,
        address _daiTokenAddress,
        uint256 _amountToTrade,
        uint256 _tokensOut
    ) public onlyOwner {
        bytes memory data = "";

        daiTokenAddress = address(_daiTokenAddress);
        dai = IERC20Token(daiTokenAddress);

        amountToTrade = _amountToTrade; // how much wei you want to trade
        tokensOut = _tokensOut; // how many tokens you want converted on the return trade

        // call lending pool to commence flash loan
        ILendingPool lendingPool = ILendingPool(
            addressesProvider.getLendingPool()
        );
        lendingPool.flashLoan(
            address(this),
            _flashAsset,
            uint256(_flashAmount),
            data
        );
    }

    /**
        Using a WETH wrapper here since there are no direct ETH pairs in Uniswap v2
        and sushiswap v1 is based on uniswap v2
     */
    function getPathForETHToToken(address ERC20Token)
        private
        view
        returns (address[] memory)
    {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = ERC20Token;

        return path;
    }

    /**
        Using a WETH wrapper to convert ERC20 token back into ETH
     */
    function getPathForTokenToETH(address ERC20Token)
        private
        view
        returns (address[] memory)
    {
        address[] memory path = new address[](2);
        path[0] = ERC20Token;
        path[1] = sushiswapV1Router.WETH();

        return path;
    }

    /**
        helper function to check ERC20 to ETH conversion rate
     */
    
    function getEstimatedETHForToken(uint256 _tokenAmount, address ERC20Token)
        public
        view
        returns (uint256[] memory)
    {
        return
            uniswapV2Router.getAmountsOut(
                _tokenAmount,
                getPathForTokenToETH(ERC20Token)
            );
    }

    /// @dev Get the conversion rate for exchanging srcQty of srcToken to destToken KYBER
    // function getConversionRates(
    //     IERC20 srcToken,
    //     IERC20 destToken,
    //     uint256 srcQty
    // ) public view returns (uint256) {
    //     return
    //         kyberProxy.getExpectedRateAfterFee(
    //             srcToken,
    //             destToken,
    //             srcQty,
    //             platformFeeBps,
    //             ""
    //         );
    // }

    function getBancorNetworkContract() public returns(IBancorNetwork){
        return IBancorNetwork(contractRegistry.addressOf('BancorNetwork'));
    }

    // function kyberSwap(uint _amount) external payable returns (uint256){
    //     return kyberProxy.tradeWithHint(
    //         dai,
    //         _amount,
    //         ERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee),
    //         address(this),
    //         8000000000000000000000000000000000000000000000000000000000000000,
    //         0,
    //             0x0000000000000000000000000000000000000004,
    //             PERM_HINT
    //         );
    // }

    function bancorSwap(
        address _sourceToken, 
        address _targetToken, 
        uint _amount
    ) public payable returns(uint returnAmount) {

        console.log('running conversionPath...');
        emit BancorSwap("msg","swap happened here. 1");
        address[] memory path;

        try bancorNetwork.conversionPath(
            _sourceToken,
            _targetToken
        ) returns (address[] memory _path)
        {
        console.log('made it here...1') ;

            path = _path;
        }  catch Error(string memory error) {
           console.log('error running conversion path', error) ;
        }

        console.log('made it here...2') ;

        // emit BancorSwap("msg","swap happened here. 2");

        console.log('running rateByPath...%s', path[0]);
        uint minReturn = bancorNetwork.rateByPath(
            path,
            _amount
        );

        // emit BancorSwap("msg","swap happened here. 3");

        console.log('running convertByPath...%d', minReturn);
        uint convertReturn = bancorNetwork.convertByPath.value(msg.value)(
            path,
            _amount,
            minReturn,
            address(0x0),
            address(0x0),
            0
        );
        console.log('done with convertByPath...');
        return convertReturn;

    }
}
