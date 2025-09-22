// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import 'hardhat/console.sol';

contract MemeToken is ERC20 {
    // 代币相关参数
    string private _name; // 代币名称
    string private _symbol; // 代币符号

    address public owner; // 合约所有者

    // 代币税相关参数
    uint256 public taxRate; // 5%的交易税
    address public taxWallet; // 税费接收地址

    // 交易限制参数
    uint256 public maxTxAmount; // 单笔交易最大金额
    uint256 public dailyTxLimit; // 每日交易次数限制
    mapping(address => uint256) public dailyTxCount; // 用户每日交易次数
    mapping(address => uint256) public lastTxDay; // 用户最后交易日期

    // Uniswap 相关
    IUniswapV2Router02 private immutable uniswapRouter;
    // 流动性 映射，记录每个地址对每个 Uniswap 对的流动性
    mapping(address => mapping(address => uint256)) public pairLiquidity;

    // 事件
    event addLiquidityEvent(uint256 tokenAmount, uint256 ethAmount, uint256 liquidity);
    event removeLiquidityEvent(uint256 tokenAmount, uint256 ethAmount);
    event swapExactTokensForETHEvent(uint256 tokenAmount, uint256 ethAmount);

    // 修饰符
    modifier onlyOwner() {
        require(msg.sender == owner, 'Only contract owner can call this function');
        _;
    }

    // 构造器
    constructor(string memory name, string memory symbol, uint256 _taxRate, address _taxWallet, uint256 _maxTxAmount, uint256 _dailyTxLimit) ERC20(name, symbol) {
        _mint(_msgSender(), 200 * 10 ** 18);

        _name = name;
        _symbol = symbol;
        taxRate = _taxRate;
        taxWallet = _taxWallet;
        maxTxAmount = _maxTxAmount;
        dailyTxLimit = _dailyTxLimit;

        // 初始化 Uniswap 相关
        uniswapRouter = IUniswapV2Router02(0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3);
        owner = _msgSender();
    }

    // 更新税费
    function setTaxRate(uint256 _taxRate) external onlyOwner {
        taxRate = _taxRate;
    }
    // 更新税费接收地址
    function setTaxWallet(address _taxWallet) external onlyOwner {
        taxWallet = _taxWallet;
    }
    // 更新单笔交易最大金额
    function setMaxTxAmount(uint256 _maxTxAmount) external onlyOwner {
        maxTxAmount = _maxTxAmount;
    }
    // 更新每日交易次数限制
    function setDailyTxLimit(uint256 _dailyTxLimit) external onlyOwner {
        dailyTxLimit = _dailyTxLimit;
    }

    // 计算交易税
    function calculateTax(uint256 amount) public view returns (uint256, uint256) {
        uint256 taxAmount = (amount * taxRate) / 100;
        return (taxAmount, amount - taxAmount);
    }

    // Meme转账函数，实现代币税和交易限制
    function _memeTransfer(uint256 amount) internal returns (uint256 taxAmount, uint256 transferAmount) {
        address sender = msg.sender;
        require(amount <= maxTxAmount, 'Exceeds maximum transaction amount');
        require(checkDailyTxLimit(sender), 'Exceeds daily transaction limit');

        // 计算交易税和实际交易数量
        (taxAmount, transferAmount) = calculateTax(amount);

        // 收取税费并分配
        _transfer(sender, taxWallet, taxAmount); // 税费给指定地址

        // 执行实际转账
        //_transfer(sender, recipient, transferAmount);

        // 更新交易限制计数器
        updateTxCount(sender);
    }

    // 检查每日交易限制
    function checkDailyTxLimit(address user) internal view returns (bool) {
        if (lastTxDay[user] != block.timestamp / 1 days) {
            return true;
        }
        return dailyTxCount[user] < dailyTxLimit;
    }

    // 更新交易计数器
    function updateTxCount(address user) internal {
        uint256 today = block.timestamp / 1 days;
        if (lastTxDay[user] != today) {
            dailyTxCount[user] = 0;
            lastTxDay[user] = today;
        }
        dailyTxCount[user]++;
    }

    // 更新代币税参数
    function updateTaxParameters(uint256 newTaxRate, address newTaxWallet) external onlyOwner {
        require(newTaxRate <= 10, 'Tax rate too high');
        taxRate = newTaxRate;
        taxWallet = newTaxWallet;
    }

    // 更新交易限制参数
    function updateTxLimits(uint256 newMaxTxAmount, uint256 newDailyTxLimit) external onlyOwner {
        maxTxAmount = newMaxTxAmount;
        dailyTxLimit = newDailyTxLimit;
    }

    // 添加流动性
    function addLiquidityForETH(uint256 amountTokenDesired, uint amountTokenMin, uint amountETHMin) external payable {
        // 实现代币税和交易限制
        (, uint256 transferAmount) = _memeTransfer(amountTokenDesired);
        // 授权 Uniswap 合约调用代币
        _approve(address(this), address(uniswapRouter), transferAmount);
        uint256 ethAmount = msg.value;
        uint deadline = block.timestamp + 1 days;
        (uint amountToken, uint amountETH, uint liquidity) = uniswapRouter.addLiquidityETH{ value: ethAmount }(address(this), transferAmount, amountTokenMin, amountETHMin, address(this), deadline);
        // 更新流动性映射
        if (pairLiquidity[address(this)][uniswapRouter.WETH()] == 0) {
            pairLiquidity[address(this)][uniswapRouter.WETH()] = liquidity;
        }
        emit addLiquidityEvent(amountToken, amountETH, liquidity);
    }

    // 移除流动性
    function removeLiquidityForETH(uint amountTokenMin, uint amountETHMin) external {
        // 获取流动性
        uint256 liquidity = pairLiquidity[address(this)][uniswapRouter.WETH()];
        require(liquidity >= 0, 'valid liquidity');
        uint deadline = block.timestamp + 1 days;
        (uint amountToken, uint amountETH) = uniswapRouter.removeLiquidityETH(address(this), liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        // 更新流动性映射
        pairLiquidity[address(this)][uniswapRouter.WETH()] = 0;
        emit removeLiquidityEvent(amountToken, amountETH);
    }

    // 交易
    function swapTokensForETH(uint256 amountIn, uint256 amountOutMin) external {
        // 实现代币税和交易限制
        (, uint256 transferAmount) = _memeTransfer(amountIn);
        // 授权 Uniswap 合约调用代币
        _approve(address(this), address(uniswapRouter), transferAmount);
        // 定义路径
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapRouter.WETH();
        uint deadline = block.timestamp + 1 days;
        uint[] memory amounts = uniswapRouter.swapExactTokensForETH(transferAmount, amountOutMin, path, address(this), deadline);
        emit swapExactTokensForETHEvent(amounts[0], amounts[1]);
    }

    receive() external payable {}

    fallback() external payable {}
}
