const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('MemeToken Liquidity', function () {
  let token;
  let owner;

  beforeEach(async function () {
    [owner] = await ethers.getSigners();

    const MemeToken = await ethers.getContractFactory('MemeToken');
    token = await MemeToken.deploy(
      'Test Token',
      'TST',
      5, // taxRate
      owner.address, // taxWallet
      1000, // maxTxAmount
      10 // dailyTxLimit
    );

    // 给测试账户分配代币
    await token.waitForDeployment();
  });

  it('Should add liquidity correctly', async function () {
    // 1. 准备测试参数
    console.log(ethers)
    const tokenAmount = ethers.parseEther('100');
    const ethAmount = ethers.parseEther('1');

    // 2. 授权合约使用代币
    await token.approve(token.address, tokenAmount);

    // 3. 调用添加流动性函数
    await expect(
      token.addLiquidityForETH(
        tokenAmount,
        0, // amountTokenMin
        0, // amountETHMin
        { value: ethAmount }
      )
    ).to.emit(token, 'addLiquidityEvent');

    // 4. 验证流动性映射
    const router = await ethers.getContractAt(
      'IUniswapV2Router02',
      '0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3'
    );
    const liquidity = await token.pairLiquidity(token.address, router.WETH());
    expect(liquidity).to.be.gt(0);
  });
});