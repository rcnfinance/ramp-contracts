
const TestToken = artifacts.require('TestToken.sol');
const FakeUniswapFactory = artifacts.require('FakeUniswapFactory.sol');
const UniswapExchange = artifacts.require('UniswapExchange.sol');
const UniswapConverter = artifacts.require('UniswapConverter.sol');
const ConverterRamp = artifacts.require('ConverterRamp.sol');

const TestModel = artifacts.require('TestModel.sol');
const TestDebtEngine = artifacts.require('DebtEngine.sol');
const TestLoanManager = artifacts.require('LoanManager.sol');
const TestRateOracle = artifacts.require('TestRateOracle.sol');

const Helper = require('./common/helper.js');
const Snap = require('./common/balanceSnap.js');

const BN = web3.utils.BN;
const expect = require('chai').use(require('bn-chai')(BN)).expect;

const ETH = new BN(10).pow(new BN(18));
const ETH_ADDRESS = '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const MAX_UINT256 = new BN(2).pow(new BN(256)).sub(new BN(1));
const MAX_UINT64 = new BN(2).pow(new BN(64)).sub(new BN(1));

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
    // Add liquidity 1 RCN => 0.00005 ETH
    const amountEthRcnLiquidity = new BN(40).mul(ETH); // 40 ETH
    const amountRcnLiquidity = amountEthRcnLiquidity.mul(new BN(20000)); // 800000 RCN
    await rcnToken.setBalance(accounts[9], amountRcnLiquidity);
    await rcnToken.approve(rcnUniswap.address, amountRcnLiquidity, { from: accounts[9] });
    await rcnUniswap.addLiquidity(
      0,
      amountRcnLiquidity,
      MAX_UINT256,
      {
        value: amountRcnLiquidity,
        from: accounts[9],
      }
    );
    // Create DEST Uniswap
    await uniswapFactory.createExchange(destToken.address);
    destUniswap = await UniswapExchange.at(await uniswapFactory.tokenToExchange(destToken.address));
    // Add liquidity 1 ETH => 200 DEST
    const amountDestLiquidity = new BN(1000000).mul(ETH); // 1000000 DEST
    const amountEthDestLiquidity = amountDestLiquidity.div(new BN(200)); // 5000 ETH
    await destToken.setBalance(accounts[9], amountDestLiquidity);
    await destToken.approve(destUniswap.address, amountDestLiquidity, { from: accounts[9] });
    await destUniswap.addLiquidity(
      0,
      amountDestLiquidity,
      MAX_UINT256,
      {
        value: amountEthDestLiquidity,
        from: accounts[9],
      }
    );
    // Create UniswapConverter
    uniswapConverter = await UniswapConverter.new(uniswapFactory.address);
  });
  async function requestLoan (amount, oracle = Helper.address0x) {
    const expiration = MAX_UINT64;
    const data = await model.encodeData(amount, expiration);

    const borrower = accounts[2];
    const creator = borrower;
    const callback = Helper.address0x;
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
    const balanceSnap = await Snap.balanceSnap(rcnToken, accounts[8]);

    await rcnToken.setBalance(accounts[8], new BN(2).pow(new BN(128)));
    await rcnToken.approve(loanManager.address, MAX_UINT256, { from: accounts[8] });

    await loanManager.lend(
      id,
      oracleData,
      Helper.address0x,
      0,
      [],
      [],
      {
        from: accounts[8],
      }
    );

    await balanceSnap.restore();
    await rcnToken.approve(loanManager.address, 0, { from: accounts[8] });

    return id;
  }
  it('Shoud lend a loan using ETH, sending the exact amount', async () => {
    const id = await requestLoan(new BN(1000).mul(ETH));

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      Helper.address0x,
      id,
      [],
      []
    );

    const ethSnap = await Snap.etherSnap(accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      ETH_ADDRESS,              // Used token
      estimated,                // Max token spend
      Helper.address0x,         // Cosigner address
      0,                        // Cosigner limit cost
      id,                       // Loan ID
      [],                       // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        value: estimated,
        gasPrice: new BN(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan using ETH, sending extra ETH amount', async () => {
    const id = await requestLoan(new BN(1001).mul(ETH));

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      Helper.address0x,
      id,
      [],
      []
    );

    const maxSpend = estimated.mul(new BN(102)).div(new BN(100)); // Send 2% more
    const ethSnap = await Snap.etherSnap(accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      ETH_ADDRESS,              // Used token
      maxSpend,                 // Max token spend
      Helper.address0x,         // Cosigner address
      0,                        // Cosigner limit cost
      id,                       // Loan ID
      [],                       // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        value: maxSpend,
        gasPrice: new BN(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equal(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan using another token, sending the exact amount', async () => {
    const id = await requestLoan(new BN(1000).mul(ETH));

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      destToken.address,
      Helper.address0x,
      id,
      [],
      []
    );

    await destToken.setBalance(accounts[5], estimated);
    await destToken.approve(converterRamp.address, estimated, { from: accounts[5] });
    const ethSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      destToken.address,        // Used token
      estimated,                // Max token spend
      Helper.address0x,         // Cosigner address
      0,                        // Cosigner limit cost
      id,                       // Loan ID
      [],                       // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        gasPrice: new BN(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan using another token, sending extra amount', async () => {
    const id = await requestLoan(new BN(1000).mul(ETH));

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      destToken.address,
      Helper.address0x,
      id,
      [],
      []
    );

    const maxSpend = estimated.mul(new BN(102)).div(new BN(100)); // Send 2% more

    await destToken.setBalance(accounts[5], maxSpend);
    await destToken.approve(converterRamp.address, maxSpend, { from: accounts[5] });
    const ethSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      destToken.address,        // Used token
      maxSpend,                 // Max token spend
      Helper.address0x,         // Cosigner address
      0,                        // Cosigner limit cost
      id,                       // Loan ID
      [],                       // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        gasPrice: new BN(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan with oracle using ETH, sending the exact amount', async () => {
    const id = await requestLoan(new BN(1000).mul(ETH), oracle.address);
    const tokens = new BN(10).pow(new BN(36));
    const equivalent = tokens.div(new BN(2));
    const oracleData = await oracle.encodeRate(tokens, equivalent);

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      Helper.address0x,
      id,
      oracleData,
      []
    );

    const ethSnap = await Snap.etherSnap(accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      ETH_ADDRESS,              // Used token
      estimated,                // Max token spend
      Helper.address0x,         // Cosigner address
      0,                        // Cosigner limit cost
      id,                       // Loan ID
      oracleData,               // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        value: estimated,
        gasPrice: new BN(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan with oracle using ETH, sending extra ETH amount', async () => {
    const id = await requestLoan(new BN(1001).mul(ETH));
    const tokens = new BN(10).pow(new BN(18));
    const equivalent = tokens.div(new BN(3));
    const oracleData = await oracle.encodeRate(tokens, equivalent);

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      Helper.address0x,
      id,
      oracleData,
      []
    );

    const maxSpend = estimated.mul(new BN(102)).div(new BN(100)); // Send 2% more
    const ethSnap = await Snap.etherSnap(accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      ETH_ADDRESS,              // Used token
      maxSpend,                 // Max token spend
      Helper.address0x,         // Cosigner address
      0,                        // Cosigner limit cost
      id,                       // Loan ID
      oracleData,               // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        value: maxSpend,
        gasPrice: new BN(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equal(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan with oracle using another token, sending the exact amount', async () => {
    const id = await requestLoan(new BN(1000).mul(ETH));
    const tokens = new BN(10).pow(new BN(40));
    const equivalent = tokens.div(new BN(18));
    const oracleData = await oracle.encodeRate(tokens, equivalent);

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      destToken.address,
      Helper.address0x,
      id,
      oracleData,
      []
    );

    await destToken.setBalance(accounts[5], estimated);
    await destToken.approve(converterRamp.address, estimated, { from: accounts[5] });
    const ethSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      destToken.address,        // Used token
      estimated,                // Max token spend
      Helper.address0x,         // Cosigner address
      0,                        // Cosigner limit cost
      id,                       // Loan ID
      oracleData,               // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        gasPrice: new BN(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud lend a loan with oracle using another token, sending extra amount', async () => {
    const id = await requestLoan(new BN(1000).mul(ETH));
    const tokens = new BN(10).pow(new BN(40));
    const equivalent = tokens.mul(new BN(18));
    const oracleData = await oracle.encodeRate(tokens, equivalent);

    const estimated = await converterRamp.getLendCost.call(
      uniswapConverter.address,
      destToken.address,
      Helper.address0x,
      id,
      oracleData,
      []
    );

    const maxSpend = estimated.mul(new BN(102)).div(new BN(100)); // Send 2% more

    await destToken.setBalance(accounts[5], maxSpend);
    await destToken.approve(converterRamp.address, maxSpend, { from: accounts[5] });
    const ethSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.lend(
      uniswapConverter.address, // Token converter
      destToken.address,        // Used token
      maxSpend,                 // Max token spend
      Helper.address0x,         // Cosigner address
      0,                        // Cosigner limit cost
      id,                       // Loan ID
      oracleData,               // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        gasPrice: new BN(0),
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it('Shoud pay a loan using ETH, sending the exact amount', async () => {
    const id = await lendLoan(await requestLoan(new BN(1000).mul(ETH)));
    const payAmount = new BN(100).mul(ETH);
    const estimated = await converterRamp.getPayCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      id,
      payAmount,
      []
    );

    const ethSnap = await Snap.etherSnap(accounts[5]);
    const engineSnap = await Snap.balanceSnap(rcnToken, debtEngine.address);

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
        gasPrice: new BN(0),
      }
    );

    expect(await model.getPaid(id)).to.eq.BN(payAmount);
    await ethSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(payAmount);
  });
  it('Shoud pay a loan using ETH, sending sending extra amount', async () => {
    const id = await lendLoan(await requestLoan(new BN(1000).mul(ETH)));
    const payAmount = new BN(100).mul(ETH);
    const estimated = await converterRamp.getPayCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      id,
      payAmount,
      []
    );

    const maxSpend = estimated.mul(new BN(102)).div(new BN(100)); // Send 2% more
    const ethSnap = await Snap.etherSnap(accounts[5]);
    const engineSnap = await Snap.balanceSnap(rcnToken, debtEngine.address);

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
        gasPrice: new BN(0),
      }
    );

    expect(await model.getPaid(id)).to.eq.BN(payAmount);
    await ethSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(payAmount);
  });
  it('Shoud pay the total amount of a loan using ETH, sending sending extra amount', async () => {
    const id = await lendLoan(await requestLoan(new BN(1000).mul(ETH)));
    const payAmount = new BN(2000).mul(ETH);
    const realPayment = new BN(1000).mul(ETH);
    const estimated = await converterRamp.getPayCost.call(
      uniswapConverter.address,
      ETH_ADDRESS,
      id,
      payAmount,
      []
    );

    const maxSpend = estimated.mul(new BN(102)).div(new BN(100)); // Send 2% more
    const ethSnap = await Snap.etherSnap(accounts[5]);
    const engineSnap = await Snap.balanceSnap(rcnToken, debtEngine.address);

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
        gasPrice: new BN(0),
      }
    );

    expect(await model.getPaid(id)).to.eq.BN(realPayment);
    await ethSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(realPayment);
  });
  it('Shoud pay a loan using another token, sending the exact amount', async () => {
    const id = await lendLoan(await requestLoan(new BN(1000).mul(ETH)));
    const payAmount = new BN(100).mul(ETH);
    const estimated = await converterRamp.getPayCost.call(
      uniswapConverter.address,
      destToken.address,
      id,
      payAmount,
      []
    );

    const engineSnap = await Snap.balanceSnap(rcnToken, debtEngine.address);
    await destToken.setBalance(accounts[5], estimated);
    await destToken.approve(converterRamp.address, estimated, { from: accounts[5] });
    const balanceSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.pay(
      uniswapConverter.address, // Token converter
      destToken.address, // Used token
      payAmount, // Amount to pay
      estimated, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        gasPrice: new BN(0),
      }
    );

    expect(await model.getPaid(id)).to.eq.BN(payAmount);
    await balanceSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(payAmount);
  });
  it('Shoud pay a loan using another token, sending sending extra amount', async () => {
    const id = await lendLoan(await requestLoan(new BN(1000).mul(ETH)));
    const payAmount = new BN(100).mul(ETH);
    const estimated = await converterRamp.getPayCost.call(
      uniswapConverter.address,
      destToken.address,
      id,
      payAmount,
      []
    );

    const maxSpend = estimated.mul(new BN(102)).div(new BN(100)); // Send 2% more
    const engineSnap = await Snap.balanceSnap(rcnToken, debtEngine.address);
    await destToken.setBalance(accounts[5], maxSpend);
    await destToken.approve(converterRamp.address, maxSpend, { from: accounts[5] });
    const balanceSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.pay(
      uniswapConverter.address, // Token converter
      destToken.address, // Used token
      payAmount, // Amount to pay
      maxSpend, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        gasPrice: new BN(0),
      }
    );

    expect(await model.getPaid(id)).to.eq.BN(payAmount);
    await balanceSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(payAmount);
  });
  it('Shoud pay the total amount of a loan using another token, sending sending extra amount', async () => {
    const id = await lendLoan(await requestLoan(new BN(1000).mul(ETH)));
    const payAmount = new BN(2000).mul(ETH);
    const realPayment = new BN(1000).mul(ETH);
    const estimated = await converterRamp.getPayCost.call(
      uniswapConverter.address,
      destToken.address,
      id,
      payAmount,
      []
    );

    const maxSpend = estimated.mul(new BN(102)).div(new BN(100)); // Send 2% more
    const engineSnap = await Snap.balanceSnap(rcnToken, debtEngine.address);
    await destToken.setBalance(accounts[5], maxSpend);
    await destToken.approve(converterRamp.address, maxSpend, { from: accounts[5] });
    const balanceSnap = await Snap.balanceSnap(destToken, accounts[5]);

    await converterRamp.pay(
      uniswapConverter.address, // Token converter
      destToken.address, // Used token
      payAmount, // Amount to pay
      maxSpend, // Max token spend
      id, // Loan ID
      [], // Oracle data
      {
        from: accounts[5],
        gasPrice: new BN(0),
      }
    );

    expect(await model.getPaid(id)).to.eq.BN(realPayment);
    await balanceSnap.requireDecrease(estimated);
    await engineSnap.requireIncrease(realPayment);
  });
});
