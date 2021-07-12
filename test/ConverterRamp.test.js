
const TestToken = artifacts.require('TestToken');
const FakeUniswapFactory = artifacts.require('FakeUniswapFactory');
const UniswapExchange = artifacts.require('IUniswapExchange');
const UniswapConverter = artifacts.require('UniswapConverter');
const ConverterRamp = artifacts.require('ConverterRamp');

const TestModel = artifacts.require('TestModel');
const TestDebtEngine = artifacts.require('DebtEngine');
const TestLoanManager = artifacts.require('LoanManager');
const TestRateOracle = artifacts.require('TestRateOracle');

const { constants } = require('@openzeppelin/test-helpers');

const {
  expect,
  bn,
  random32,
  ETH_ADDRESS,
  MAX_UINT64,
  toETH,
  balanceSnap,
  etherSnap,
} = require('./Helper.js');

contract('ConverterRamp', function (accounts) {
  let rcnToken;
  let destToken;
  let debtEngine;
  let loanManager;
  let model;
  let oracle;
  let converterRamp;
  let uniswapFactory;
  let rcnUniswap;
  let destUniswap;
  let uniswapConverter;

  async function requestLoan (amount, oracle = constants.ZERO_ADDRESS) {
    const expiration = MAX_UINT64;
    const data = await model.encodeData(amount, expiration);

    const borrower = accounts[2];
    const creator = borrower;
    const callback = constants.ZERO_ADDRESS;
    const salt = random32();

    const id = await loanManager.calcId(
      amount,
      borrower,
      creator,
      model.address,
      oracle,
      callback,
      salt,
      expiration,
      data
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
      }
    );

    return id;
  }

  async function lendLoan (id, oracleData = []) {
    const balSnap = await balanceSnap(rcnToken, accounts[8]);

    await rcnToken.setBalance(accounts[8], bn(2).pow(bn(128)));
    await rcnToken.approve(loanManager.address, constants.MAX_UINT256, { from: accounts[8] });

    await loanManager.lend(
      id,
      oracleData,
      constants.ZERO_ADDRESS,
      0,
      [],
      [],
      {
        from: accounts[8],
      }
    );

    await balSnap.restore();
    await rcnToken.approve(loanManager.address, 0, { from: accounts[8] });

    return id;
  }

  before('Deploy RCN contracts', async () => {
    // Deploy DEST and TEST tokens
    rcnToken = await TestToken.new();
    destToken = await TestToken.new();

    // Deploy RCN mini-ecosystem
    debtEngine = await TestDebtEngine.new(rcnToken.address);
    loanManager = await TestLoanManager.new(debtEngine.address);
    model = await TestModel.new();
    await model.setEngine(debtEngine.address);
    oracle = await TestRateOracle.new();

    // Deploy converter ramp
    converterRamp = await ConverterRamp.new(loanManager.address);
  });

  beforeEach('Deploy contracts', async () => {
    // Deploy Uniswap, cheate exchanges and
    // fund pools
    uniswapFactory = await FakeUniswapFactory.new();
    // Create RCN (TEST) Uniswap
    await uniswapFactory.createExchange(rcnToken.address);
    rcnUniswap = await UniswapExchange.at(await uniswapFactory.tokenToExchange(rcnToken.address));
    // Add liquidity 1 RCN => 200 ETH
    const amountEthRcnLiquidity = toETH(0.4); // 0.4 ETH
    const amountRcnLiquidity = amountEthRcnLiquidity.mul(bn(200)); // 80 RCN
    await rcnToken.setBalance(accounts[9], amountRcnLiquidity);
    await rcnToken.approve(rcnUniswap.address, amountRcnLiquidity, { from: accounts[9] });
    await rcnUniswap.addLiquidity(
      0,
      amountRcnLiquidity,
      constants.MAX_UINT256,
      {
        value: amountEthRcnLiquidity,
        from: accounts[9],
      }
    );
    // Create DEST Uniswap
    await uniswapFactory.createExchange(destToken.address);
    destUniswap = await UniswapExchange.at(await uniswapFactory.tokenToExchange(destToken.address));
    // Add liquidity 1 ETH => 200 DEST
    const amountDestLiquidity = toETH(0.1); // 0.1 DEST
    const amountEthDestLiquidity = amountDestLiquidity.div(bn(200)); // 20 ETH
    await destToken.setBalance(accounts[9], amountDestLiquidity);
    await destToken.approve(destUniswap.address, amountDestLiquidity, { from: accounts[9] });
    await destUniswap.addLiquidity(
      0,
      amountDestLiquidity,
      constants.MAX_UINT256,
      {
        value: amountEthDestLiquidity,
        from: accounts[9],
      }
    );
    // Create UniswapConverter
    uniswapConverter = await UniswapConverter.new(uniswapFactory.address);
  });

  it('Shoud lend a loan using ETH, sending the exact amount', async () => {
    const id = await requestLoan(toETH(0.01));

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      constants.ZERO_ADDRESS,
      id,
      [],
      []
    );

    const ethSnap = await etherSnap(accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      ETH_ADDRESS, // Used token
      estimated, // Max token spend
      constants.ZERO_ADDRESS, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      [], // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        value: estimated,
        gasPrice: bn(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan using ETH, sending extra ETH amount', async () => {
    const id = await requestLoan(toETH(0.01001));

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      constants.ZERO_ADDRESS,
      id,
      [],
      []
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more
    const ethSnap = await etherSnap(accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      ETH_ADDRESS, // Used token
      maxSpend, // Max token spend
      constants.ZERO_ADDRESS, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      [], // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        value: maxSpend,
        gasPrice: bn(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equal(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan using another token, sending the exact amount', async () => {
    const id = await requestLoan(toETH(0.01));

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      destToken.address,
      constants.ZERO_ADDRESS,
      id,
      [],
      []
    );

    await destToken.setBalance(accounts[5], estimated);
    await destToken.approve(converterRamp.address, estimated, { from: accounts[5] });
    const ethSnap = await balanceSnap(destToken, accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      destToken.address, // Used token
      estimated, // Max token spend
      constants.ZERO_ADDRESS, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      [], // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        gasPrice: bn(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan using another token, sending extra amount', async () => {
    const id = await requestLoan(toETH(0.01));

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      destToken.address,
      constants.ZERO_ADDRESS,
      id,
      [],
      []
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more

    await destToken.setBalance(accounts[5], maxSpend);
    await destToken.approve(converterRamp.address, maxSpend, { from: accounts[5] });
    const ethSnap = await balanceSnap(destToken, accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      destToken.address, // Used token
      maxSpend, // Max token spend
      constants.ZERO_ADDRESS, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      [], // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        gasPrice: bn(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan with oracle using ETH, sending the exact amount', async () => {
    const id = await requestLoan(toETH(0.01), oracle.address);
    const tokens = bn(10).pow(bn(18));
    const equivalent = tokens.div(bn(2));
    const oracleData = await oracle.encodeRate(tokens, equivalent);

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      constants.ZERO_ADDRESS,
      id,
      oracleData,
      []
    );

    const ethSnap = await etherSnap(accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      ETH_ADDRESS, // Used token
      estimated, // Max token spend
      constants.ZERO_ADDRESS, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      oracleData, // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        value: estimated,
        gasPrice: bn(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan with oracle using ETH, sending extra ETH amount', async () => {
    const id = await requestLoan(toETH(0.01001));
    const tokens = bn(10).pow(bn(18));
    const equivalent = tokens.div(bn(3));
    const oracleData = await oracle.encodeRate(tokens, equivalent);

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      constants.ZERO_ADDRESS,
      id,
      oracleData,
      []
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more
    const ethSnap = await etherSnap(accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      ETH_ADDRESS, // Used token
      maxSpend, // Max token spend
      constants.ZERO_ADDRESS, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      oracleData, // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        value: maxSpend,
        gasPrice: bn(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equal(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan with oracle using another token, sending the exact amount', async () => {
    const id = await requestLoan(toETH(0.01));
    const tokens = bn(10).pow(bn(20));
    const equivalent = tokens.div(bn(18));
    const oracleData = await oracle.encodeRate(tokens, equivalent);

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      destToken.address,
      constants.ZERO_ADDRESS,
      id,
      oracleData,
      []
    );

    await destToken.setBalance(accounts[5], estimated);
    await destToken.approve(converterRamp.address, estimated, { from: accounts[5] });
    const ethSnap = await balanceSnap(destToken, accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      destToken.address, // Used token
      estimated, // Max token spend
      constants.ZERO_ADDRESS, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      oracleData, // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        gasPrice: bn(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan with oracle using another token, sending extra amount', async () => {
    const id = await requestLoan(toETH(0.01));
    const tokens = bn(10).pow(bn(20));
    const equivalent = tokens.mul(bn(18));
    const oracleData = await oracle.encodeRate(tokens, equivalent);

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      destToken.address,
      constants.ZERO_ADDRESS,
      id,
      oracleData,
      []
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more

    await destToken.setBalance(accounts[5], maxSpend);
    await destToken.approve(converterRamp.address, maxSpend, { from: accounts[5] });
    const ethSnap = await balanceSnap(destToken, accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      destToken.address, // Used token
      maxSpend, // Max token spend
      constants.ZERO_ADDRESS, // Cosigner address
      0, // Cosigner limit cost
      id, // Loan ID
      oracleData, // Oracle data
      [], // Cosigner data
      [], // Callback data
      {
        from: accounts[5],
        gasPrice: bn(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud pay a loan using ETH, sending the exact amount', async () => {
    const id = await lendLoan(await requestLoan(toETH(0.01)));
    const payAmount = toETH(0.001);
    const estimated = await converterRamp.getPayCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      id,
      payAmount,
      []
    );

    const ethSnap = await etherSnap(accounts[5]);
    const engineSnap = await balanceSnap(rcnToken, debtEngine.address);

    await converterRamp.pay(
      uniswapConverter.address, // Token converter
      ETH_ADDRESS, // Used token
      payAmount, // Amount to pay
      estimated, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        value: estimated,
        gasPrice: bn(0),
      }
    );

    expect(await model.getPaid(id)).to.eq.BN(payAmount);
    await ethSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(payAmount);
  });
  it('Shoud pay a loan using ETH, sending sending extra amount', async () => {
    const id = await lendLoan(await requestLoan(toETH(0.01)));
    const payAmount = toETH(0.001);
    const estimated = await converterRamp.getPayCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      id,
      payAmount,
      []
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more
    const ethSnap = await etherSnap(accounts[5]);
    const engineSnap = await balanceSnap(rcnToken, debtEngine.address);

    await converterRamp.pay(
      uniswapConverter.address, // Token converter
      ETH_ADDRESS, // Used token
      payAmount, // Amount to pay
      maxSpend, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        value: maxSpend,
        gasPrice: bn(0),
      }
    );

    expect(await model.getPaid(id)).to.eq.BN(payAmount);
    await ethSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(payAmount);
  });
  it('Shoud pay the total amount of a loan using ETH, sending sending extra amount', async () => {
    const id = await lendLoan(await requestLoan(toETH(0.01)));
    const payAmount = toETH(0.02);
    const realPayment = toETH(0.01);
    const estimated = await converterRamp.getPayCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      id,
      payAmount,
      []
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more
    const ethSnap = await etherSnap(accounts[5]);
    const engineSnap = await balanceSnap(rcnToken, debtEngine.address);

    await converterRamp.pay(
      uniswapConverter.address, // Token converter
      ETH_ADDRESS, // Used token
      payAmount, // Amount to pay
      maxSpend, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        value: maxSpend,
        gasPrice: bn(0),
      }
    );

    expect(await model.getPaid(id)).to.eq.BN(realPayment);
    await ethSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(realPayment);
  });
  it('Shoud pay a loan using another token, sending the exact amount', async () => {
    const id = await lendLoan(await requestLoan(toETH(0.01)));
    const payAmount = toETH(0.001);
    const estimated = await converterRamp.getPayCost.call(
      uniswapConverter.address,
      destToken.address,
      id,
      payAmount,
      []
    );

    const engineSnap = await balanceSnap(rcnToken, debtEngine.address);
    await destToken.setBalance(accounts[5], estimated);
    await destToken.approve(converterRamp.address, estimated, { from: accounts[5] });
    const balSnap = await balanceSnap(destToken, accounts[5]);

    await converterRamp.pay(
      uniswapConverter.address, // Token converter
      destToken.address, // Used token
      payAmount, // Amount to pay
      estimated, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        gasPrice: bn(0),
      }
    );

    expect(await model.getPaid(id)).to.eq.BN(payAmount);
    await balSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(payAmount);
  });
  it('Shoud pay a loan using another token, sending sending extra amount', async () => {
    const id = await lendLoan(await requestLoan(toETH(0.1)));
    const payAmount = toETH(0.001);
    const estimated = await converterRamp.getPayCost.call(
      uniswapConverter.address,
      destToken.address,
      id,
      payAmount,
      []
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more
    const engineSnap = await balanceSnap(rcnToken, debtEngine.address);
    await destToken.setBalance(accounts[5], maxSpend);
    await destToken.approve(converterRamp.address, maxSpend, { from: accounts[5] });
    const balSnap = await balanceSnap(destToken, accounts[5]);

    await converterRamp.pay(
      uniswapConverter.address, // Token converter
      destToken.address, // Used token
      payAmount, // Amount to pay
      maxSpend, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        gasPrice: bn(0),
      }
    );

    expect(await model.getPaid(id)).to.eq.BN(payAmount);
    await balSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(payAmount);
  });
  it('Shoud pay the total amount of a loan using another token, sending sending extra amount', async () => {
    const id = await lendLoan(await requestLoan(toETH(0.01)));
    const payAmount = toETH(0.02);
    const realPayment = toETH(0.01);
    const estimated = await converterRamp.getPayCost.call(
      uniswapConverter.address,
      destToken.address,
      id,
      payAmount,
      []
    );

    const maxSpend = estimated.mul(bn(102)).div(bn(100)); // Send 2% more
    const engineSnap = await balanceSnap(rcnToken, debtEngine.address);
    await destToken.setBalance(accounts[5], maxSpend);
    await destToken.approve(converterRamp.address, maxSpend, { from: accounts[5] });
    const balSnap = await balanceSnap(destToken, accounts[5]);

    await converterRamp.pay(
      uniswapConverter.address, // Token converter
      destToken.address, // Used token
      payAmount, // Amount to pay
      maxSpend, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        gasPrice: bn(0),
      }
    );

    expect(await model.getPaid(id)).to.eq.BN(realPayment);
    await balSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(realPayment);
  });
});
