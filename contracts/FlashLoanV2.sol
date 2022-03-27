//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract FlashLoanV2 is IUniswapV2Callee {
    address immutable tokenA;
    address immutable tokenB;
    address immutable factory;
    address immutable swapRouter;
    address immutable devAddress;
    uint24 public constant poolFee = 3000;

    event RecievedTokenFromV3(
        address loanToken,
        address tokenRecieve,
        uint256 amountOut,
        address _to
    );
    event RepayTokenFromV2(
        uint256 amountRequired,
        uint256 amountOut,
        uint256 winAmount,
        address devAddress
    );
    event LoanTokenFromPair(address _loanToken, uint256 _amount, address pair);

    constructor(
        address _tokenA,
        address _tokenB,
        address _factory,
        address _swapRouter,
        address _devAddress
    ) {
        tokenA = _tokenA;
        tokenB = _tokenB;
        factory = _factory;
        swapRouter = _swapRouter;
        devAddress = _devAddress;
    }

    function flashSwap(address _loanToken, uint256 _amount) public {
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "the swap pair not exists");
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        uint256 amount0Out = _loanToken == token0 ? _amount : 0;
        uint256 amount1Out = _loanToken == token1 ? _amount : 0;
        bytes memory data = abi.encode(_loanToken, _amount);
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), data);
        emit LoanTokenFromPair(_loanToken, _amount, pair);
    }

    function uniswapV2Call(
        address _sender,
        uint256 _amount0,
        uint256 _amount1,
        bytes calldata _data
    ) external override {
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        address pair = IUniswapV2Factory(factory).getPair(token0, token1);
        require(msg.sender == pair, "the caller is not pair contract");
        require(_sender == address(this), "not the sender");
        (address loanToken, uint256 amountToken) = abi.decode(
            _data,
            (address, uint256)
        );
        //调用uniswap v3 swap token
        TransferHelper.safeApprove(loanToken, address(swapRouter), amountToken);
        address tokenRecieve = loanToken == tokenA ? tokenB : tokenA;
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: loanToken,
                tokenOut: tokenRecieve,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountToken,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        //调用v3 swap获得的代币数量
        uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
        emit RecievedTokenFromV3(
            loanToken,
            tokenRecieve,
            amountOut,
            address(this)
        );
        //获取需要还的代币数量
        address[] memory path = new address[](2);
        path[0] = _amount0 == 0 ? token0 : token1;
        path[1] = _amount0 == 0 ? token1 : token0;
        uint256 amountRequired = UniswapV2Library.getAmountsIn(
            factory,
            amountToken,
            path
        )[0];
        assert(amountOut > amountRequired); // 如果交换获取的代币数量小于等于需要还的数量那就失败了
        IERC20(tokenRecieve).transfer(pair, amountRequired); //还款给配对合约
        IERC20(tokenRecieve).transfer(devAddress, amountOut - amountRequired); //套利所得给开发者
        emit RepayTokenFromV2(
            amountRequired,
            amountOut,
            amountOut - amountRequired,
            devAddress
        );
    }
}
