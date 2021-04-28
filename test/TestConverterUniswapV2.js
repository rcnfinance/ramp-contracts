const TestToken = artifacts.require('TestToken.sol');
const WETH9 = artifacts.require('WETH9');
const UniswapV2Factory = artifacts.require('UniswapV2Factory');
const UniswapV2Router = artifacts.require('UniswapV2Router02');
const UniswapV2Converter = artifacts.require('UniswapV2Converter');
const ConverterRamp = artifacts.require('ConverterRamp');
const UniRoute = artifacts.require('UniRoute');

const TestModel = artifacts.require('TestModel');
const TestDebtEngine = artifacts.require('DebtEngine');
const TestLoanManager = artifacts.require('LoanManager');
const TestRateOracle = artifacts.require('TestRateOracle');

const {
  expect,
  bn,
  address0x,
  toETH,
} = require('./common/helper.js');
const Snap = require('./common/balanceSnap.js');

const ETH_ADDRESS = '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const MAX_UINT256 = bn(2).pow(bn(256)).sub(bn(1));
const MAX_UINT64 = bn(2).pow(bn(64)).sub(bn(1));

contract('ConverterRamp with Uniswap V2', function (accounts) {
  const owner = accounts[1];
  const burner = accounts[5];

  let rcnToken;
  let destToken;
  let debtEngine;
  let loanManager;
  let model;
  let oracle;
  let converterRamp;
  let uniswapV2Factory;
  let uniswapV2Converter;
  let router;
  let weth;

  async function addLiquidity (tokenA, tokenB, amountA, amountB) {
    await tokenA.setBalance(owner, amountA);
    await tokenA.approve(router.address, amountA, { from: owner });
    await tokenB.setBalance(owner, amountB);
    await tokenB.approve(router.address, amountB, { from: owner });

    await router.addLiquidity(
      tokenA.address,
      tokenB.address,
      amountA,
      amountB,
      1,
      1,
      owner,
      bn('999999999999999999999999999999'),
      { from: owner },
    );
  }

  async function addLiquidityETH (tokenA, amountETH, amountA) {
    await tokenA.setBalance(owner, amountA);
    await tokenA.approve(router.address, amountA, { from: owner });

    await router.addLiquidityETH(
      tokenA.address,
      amountA,
      1,
      1,
      owner,
      '9999999999999999999999999999999',
      { from: owner, value: amountETH },
    );
  }

  async function requestLoan (amount, oracle = address0x) {
    const expiration = MAX_UINT64;
    const data = await model.encodeData(amount, expiration, 0, expiration);

    const borrower = accounts[2];
    const creator = borrower;
    const callback = address0x;
    const salt = new Date().getTime();

    const id = await loanManager.calcId(
      amount,
      borrower,
      creator,
      model.address,
      oracle,
      callback,
      salt,
      expiration,
      data,
    );

    await loanManager.requestLoan(
      amount,
      model.address,
      oracle,
      borrower,
      callback,
      salt,
      expiration,
      data,
      {
        from: creator,
      },
    );

    return id;
  }

  async function lendLoan (id, oracleData = []) {
    const balanceSnap = await Snap.balanceSnap(rcnToken, accounts[8]);

    await rcnToken.setBalance(accounts[8], bn(2).pow(bn(128)));
    await rcnToken.approve(loanManager.address, MAX_UINT256, { from: accounts[8] });

    await loanManager.lend(
      id,
      oracleData,
      address0x,
      0,
      [],
      [],
      {
        from: accounts[8],
      },
    );

    await balanceSnap.restore();
    await rcnToken.approve(loanManager.address, 0, { from: accounts[8] });

    return id;
  }

  before('Deploy RCN contracts', async () => {
    // Deploy DEST and TEST tokens
    rcnToken = await TestToken.new();
    destToken = await TestToken.new();

    // Deploy RCN mini-ecosystem
    debtEngine = await TestDebtEngine.new(rcnToken.address, burner, 100, { from: owner });
    loanManager = await TestLoanManager.new(debtEngine.address);
    model = await TestModel.new();
    await model.setEngine(debtEngine.address);
    oracle = await TestRateOracle.new();

    // Deploy WETH
    weth = await WETH9.new();

    // Deploy Uniswap V2
    uniswapV2Factory = await UniswapV2Factory.new(owner);
    router = await UniswapV2Router.new(uniswapV2Factory.address, weth.address);
    // Add liquidity
    await addLiquidity(rcnToken, destToken, toETH(20000), toETH(1000000));
    await addLiquidityETH(rcnToken, toETH(40), toETH(20000));
    await addLiquidityETH(destToken, toETH(40), toETH(20000));

    // Deploy converter ramp
    uniRoute = await UniRoute.new();
    uniswapV2Converter = await UniswapV2Converter.new(router.address, uniRoute.address);
    converterRamp = await ConverterRamp.new(loanManager.address);

    // Set UniRoutes
    await uniRoute.setPath(destToken.address, rcnToken.address, [destToken.address, weth.address, rcnToken.address])
    await uniRoute.setPath(ETH_ADDRESS, rcnToken.address, [weth.address, rcnToken.address])
  });

  it('Shoud lend a loan using ETH, sending the exact amount', async () => {
    const id = await requestLoan(toETH(1000));

    const estimated = await converterRamp.getLendCost.call(
      uniswapV2Converter.address,
      ETH_ADDRESS,
      address0x,
      id,
      [],
      [],
    );

    const ethSnap = await Snap.etherSnap(accounts[5]);

    await converterRamp.lend(
      uniswapV2Converter.address, // Token converter
      ETH_ADDRESS, // Used token
      estimated, // Max token spend
      address0x, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      [], // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        value: estimated,
        gasPrice: 0,
      },
    );

    assert.equal(await debtEngine.ownerOf(id), accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan using ETH, sending extra ETH amount', async () => {
    const id = await requestLoan(toETH(1001));

    const estimated = await converterRamp.getLendCost.call(
      uniswapV2Converter.address,
      ETH_ADDRESS,
      address0x,
      id,
      [],
      [],
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more
    const ethSnap = await Snap.etherSnap(accounts[5]);

    await converterRamp.lend(
      uniswapV2Converter.address, // Token converter
      ETH_ADDRESS, // Used token
      maxSpend, // Max token spend
      address0x, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      [], // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        value: maxSpend,
        gasPrice: 0,
      },
    );

    assert.equal(await debtEngine.ownerOf(id), accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan using another token, sending the exact amount', async () => {
    const id = await requestLoan(toETH(1000));

    const estimated = await converterRamp.getLendCost.call(
      uniswapV2Converter.address,
      destToken.address,
      address0x,
      id,
      [],
      [],
    );

    await destToken.setBalance(accounts[5], estimated);
    await destToken.approve(converterRamp.address, estimated, { from: accounts[5] });
    const ethSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.lend(
      uniswapV2Converter.address, // Token converter
      destToken.address, // Used token
      estimated, // Max token spend
      address0x, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      [], // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        gasPrice: 0,
      },
    );

    assert.equal(await debtEngine.ownerOf(id), accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan using another token, sending extra amount', async () => {
    const id = await requestLoan(toETH(1000));

    const estimated = await converterRamp.getLendCost.call(
      uniswapV2Converter.address,
      destToken.address,
      address0x,
      id,
      [],
      [],
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more

    await destToken.setBalance(accounts[5], maxSpend);
    await destToken.approve(converterRamp.address, maxSpend, { from: accounts[5] });
    const ethSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.lend(
      uniswapV2Converter.address, // Token converter
      destToken.address, // Used token
      maxSpend, // Max token spend
      address0x, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      [], // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        gasPrice: 0,
      },
    );

    assert.equal(await debtEngine.ownerOf(id), accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan with oracle using ETH, sending the exact amount', async () => {
    const id = await requestLoan(toETH(1000), oracle.address);
    const tokens = bn(10).pow(bn(18));
    const equivalent = tokens.div(bn(2));
    const oracleData = await oracle.encodeRate(tokens, equivalent);

    const estimated = await converterRamp.getLendCost.call(
      uniswapV2Converter.address,
      ETH_ADDRESS,
      address0x,
      id,
      oracleData,
      [],
    );

    const ethSnap = await Snap.etherSnap(accounts[5]);

    await converterRamp.lend(
      uniswapV2Converter.address, // Token converter
      ETH_ADDRESS, // Used token
      estimated, // Max token spend
      address0x, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      oracleData, // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        value: estimated,
        gasPrice: 0,
      },
    );

    assert.equal(await debtEngine.ownerOf(id), accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan with oracle using ETH, sending extra ETH amount', async () => {
    const id = await requestLoan(toETH(1001));

    const estimated = await converterRamp.getLendCost.call(
      uniswapV2Converter.address,
      ETH_ADDRESS,
      address0x,
      id,
      [],
      [],
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more
    const ethSnap = await Snap.etherSnap(accounts[5]);

    await converterRamp.lend(
      uniswapV2Converter.address, // Token converter
      ETH_ADDRESS, // Used token
      maxSpend, // Max token spend
      address0x, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      [], // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        value: maxSpend,
        gasPrice: 0,
      },
    );

    assert.equal(await debtEngine.ownerOf(id), accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan with oracle using another token, sending the exact amount', async () => {
    const id = await requestLoan(toETH(1000));

    const estimated = await converterRamp.getLendCost.call(
      uniswapV2Converter.address,
      destToken.address,
      address0x,
      id,
      [],
      [],
    );

    await destToken.setBalance(accounts[5], estimated);
    await destToken.approve(converterRamp.address, estimated, { from: accounts[5] });
    const ethSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.lend(
      uniswapV2Converter.address, // Token converter
      destToken.address, // Used token
      estimated, // Max token spend
      address0x, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      [], // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        gasPrice: 0,
      },
    );

    assert.equal(await debtEngine.ownerOf(id), accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan with oracle using another token, sending extra amount', async () => {
    const id = await requestLoan(toETH(1000));

    const estimated = await converterRamp.getLendCost.call(
      uniswapV2Converter.address,
      destToken.address,
      address0x,
      id,
      [],
      [],
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more

    await destToken.setBalance(accounts[5], maxSpend);
    await destToken.approve(converterRamp.address, maxSpend, { from: accounts[5] });
    const ethSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.lend(
      uniswapV2Converter.address, // Token converter
      destToken.address, // Used token
      maxSpend, // Max token spend
      address0x, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      [], // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        gasPrice: 0,
      },
    );

    assert.equal(await debtEngine.ownerOf(id), accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud pay a loan using ETH, sending the exact amount', async () => {
    const id = await lendLoan(await requestLoan(toETH(100)));
    const payAmount = toETH(10);
    const estimated = await converterRamp.getPayCostWithFee.call(
      uniswapV2Converter.address,
      ETH_ADDRESS,
      id,
      payAmount,
      [],
    );

    const ethSnap = await Snap.etherSnap(accounts[5]);
    const engineSnap = await Snap.balanceSnap(rcnToken, debtEngine.address);

    await converterRamp.pay(
      uniswapV2Converter.address, // Token converter
      ETH_ADDRESS, // Used token
      payAmount, // Amount to pay
      estimated, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        value: estimated,
        gasPrice: 0,
      },
    );

    expect(await model.getPaid(id)).to.eq.BN(payAmount);
    await ethSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(payAmount);
  });
  it('Shoud pay a loan using ETH, sending sending extra amount', async () => {
    const id = await lendLoan(await requestLoan(toETH(1000)));
    const payAmount = toETH(100);
    const estimated = await converterRamp.getPayCostWithFee.call(
      uniswapV2Converter.address,
      ETH_ADDRESS,
      id,
      payAmount,
      [],
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more
    const ethSnap = await Snap.etherSnap(accounts[5]);
    const engineSnap = await Snap.balanceSnap(rcnToken, debtEngine.address);

    await converterRamp.pay(
      uniswapV2Converter.address, // Token converter
      ETH_ADDRESS, // Used token
      payAmount, // Amount to pay
      maxSpend, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        value: maxSpend,
        gasPrice: 0,
      },
    );

    expect(await model.getPaid(id)).to.eq.BN(payAmount);
    await ethSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(payAmount);
  });
  it('Shoud pay the total amount of a loan using ETH, sending sending extra amount', async () => {
    const id = await lendLoan(await requestLoan(toETH(1000)));
    const payAmount = toETH(2000);
    const realPayment = toETH(1000);
    const estimated = await converterRamp.getPayCostWithFee.call(
      uniswapV2Converter.address,
      ETH_ADDRESS,
      id,
      payAmount,
      [],
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more
    const ethSnap = await Snap.etherSnap(accounts[5]);
    const engineSnap = await Snap.balanceSnap(rcnToken, debtEngine.address);

    await converterRamp.pay(
      uniswapV2Converter.address, // Token converter
      ETH_ADDRESS, // Used token
      payAmount, // Amount to pay
      maxSpend, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        value: maxSpend,
        gasPrice: 0,
      },
    );

    expect(await model.getPaid(id)).to.eq.BN(realPayment);
    await ethSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(realPayment);
  });
  it('Shoud pay a loan using another token, sending the exact amount', async () => {
    const id = await lendLoan(await requestLoan(toETH(1000)));
    const payAmount = toETH(100);
    const estimated = await converterRamp.getPayCostWithFee.call(
      uniswapV2Converter.address,
      destToken.address,
      id,
      payAmount,
      [],
    );

    const engineSnap = await Snap.balanceSnap(rcnToken, debtEngine.address);
    await destToken.setBalance(accounts[5], estimated);
    await destToken.approve(converterRamp.address, estimated, { from: accounts[5] });
    const balanceSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.pay(
      uniswapV2Converter.address, // Token converter
      destToken.address, // Used token
      payAmount, // Amount to pay
      estimated, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        gasPrice: 0,
      },
    );

    expect(await model.getPaid(id)).to.eq.BN(payAmount);
    await balanceSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(payAmount);
  });
  it('Shoud pay a loan using another token, sending sending extra amount', async () => {
    const id = await lendLoan(await requestLoan(toETH(1000)));
    const payAmount = toETH(100);
    const estimated = await converterRamp.getPayCostWithFee.call(
      uniswapV2Converter.address,
      destToken.address,
      id,
      payAmount,
      [],
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more
    const engineSnap = await Snap.balanceSnap(rcnToken, debtEngine.address);
    await destToken.setBalance(accounts[5], maxSpend);
    await destToken.approve(converterRamp.address, maxSpend, { from: accounts[5] });
    const balanceSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.pay(
      uniswapV2Converter.address, // Token converter
      destToken.address, // Used token
      payAmount, // Amount to pay
      maxSpend, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        gasPrice: 0,
      },
    );

    expect(await model.getPaid(id)).to.eq.BN(payAmount);
    await balanceSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(payAmount);
  });
  it('Shoud pay the total amount of a loan using another token, sending sending extra amount', async () => {
    const id = await lendLoan(await requestLoan(toETH(1000)));
    const payAmount = toETH(2000);
    const realPayment = toETH(1000);
    const estimated = await converterRamp.getPayCostWithFee.call(
      uniswapV2Converter.address,
      destToken.address,
      id,
      payAmount,
      [],
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more
    const engineSnap = await Snap.balanceSnap(rcnToken, debtEngine.address);
    await destToken.setBalance(accounts[5], maxSpend);
    await destToken.approve(converterRamp.address, maxSpend, { from: accounts[5] });
    const balanceSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.pay(
      uniswapV2Converter.address, // Token converter
      destToken.address, // Used token
      payAmount, // Amount to pay
      maxSpend, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        gasPrice: 0,
      },
    );

    expect(await model.getPaid(id)).to.eq.BN(realPayment);
    await balanceSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(realPayment);
  });
});
