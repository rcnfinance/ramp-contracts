const TestToken = artifacts.require('TestToken.sol');
const TestConverter = artifacts.require('TestConverter');
const TestCosigner = artifacts.require('TestCosigner');
const ConverterRamp = artifacts.require('ConverterRamp');

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

const ETH_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
const MAX_UINT256 = bn(2).pow(bn(256)).sub(bn(1));
const MAX_UINT64 = bn(2).pow(bn(64)).sub(bn(1));

contract('ConverterRamp', function (accounts) {
  const owner = accounts[1];
  const burner = accounts[5];

  let rcnToken;
  let testToken;
  let debtEngine;
  let loanManager;
  let model;
  let oracle;
  let converterRamp;
  let converter;
  let cosigner;

  async function toFee (amount) {
    const feePerc = await debtEngine.fee();
    const BASE = await debtEngine.BASE();

    if (amount.mul(feePerc).mod(BASE).isZero())
      return amount.mul(feePerc).div(BASE);
    else
      return amount.mul(feePerc).div(BASE).add(bn(1));
  }

  async function withFee (amount) {
    return amount.add(await toFee(amount));
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
    if (await loanManager.getOracle(id) !== address0x)
      oracleData = await oracle.encodeRate(toETH(), toETH());

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

    return id;
  }

  before('Deploy RCN contracts', async () => {
    // Deploy DEST and TEST tokens
    rcnToken = await TestToken.new();
    testToken = await TestToken.new();

    // Deploy RCN mini-ecosystem
    debtEngine = await TestDebtEngine.new(rcnToken.address, burner, 100, { from: owner });
    loanManager = await TestLoanManager.new(debtEngine.address);
    model = await TestModel.new();
    await model.setEngine(debtEngine.address);
    oracle = await TestRateOracle.new();
    converter = await TestConverter.new();
    cosigner = await TestCosigner.new();

    // Deploy converter ramp
    converterRamp = await ConverterRamp.new(loanManager.address);
  });

  it('Check the debtEngine, loanManager and debtEngineToken', async () => {
    const converterRamp = await ConverterRamp.new(loanManager.address);

    assert.equal(await converterRamp.debtEngine(), debtEngine.address);
    assert.equal(await converterRamp.loanManager(), loanManager.address);
    assert.equal(await converterRamp.debtEngineToken(), await debtEngine.token());
  });
  it('ETH_ADDRESS', async () => {
    assert.equal(await converterRamp.ETH_ADDRESS(), ETH_ADDRESS);
  });
  describe('Function getLendCost', () => {
    it('Base', async () => {
      const loanAmount = bn(1000);
      const id = await requestLoan(loanAmount);

      const lendCost = await converterRamp.getLendCost.call(
        converter.address, // converter
        testToken.address, // fromToken
        address0x,         // cosigner
        id,                // requestId
        [],                // oracleData
        []                 // cosignerData
      );

      expect(lendCost).to.eq.BN(loanAmount);
    });
    it('With cosigner cost', async () => {
      const loanAmount = bn(1000);
      const cosignerCost = bn(1234);
      const id = await requestLoan(loanAmount);

      await cosigner.setCustomData(id, cosignerCost);

      const lendCost = await converterRamp.getLendCost.call(
        converter.address, // converter
        testToken.address, // fromToken
        cosigner.address,  // cosigner
        id,                // requestId
        [],                // oracleData
        []                 // cosignerData
      );

      expect(lendCost).to.eq.BN(loanAmount.add(cosignerCost));
    });
    it('With cosigner cost and oracle', async () => {
      const loanAmount = bn(1000);
      const cosignerCost = bn(1234);
      const id = await requestLoan(loanAmount, oracle.address);

      const oracleData = await oracle.encodeRate(toETH(), toETH().mul(bn(2)));
      await cosigner.setCustomData(id, cosignerCost);

      const lendCost = await converterRamp.getLendCost.call(
        converter.address, // converter
        testToken.address, // fromToken
        cosigner.address,  // cosigner
        id,                // requestId
        oracleData,        // oracleData
        []                 // cosignerData
      );

      expect(lendCost).to.eq.BN(loanAmount.add(cosignerCost).div(bn(2)));
    });
  });
  describe('Function getPayCostWithFee', () => {
    it('Loan without lend', async () => {
      const loanAmount = bn(1000);
      const id = await requestLoan(loanAmount);

      const payCost = await converterRamp.getPayCostWithFee.call(
        converter.address, // converter
        testToken.address, // fromToken
        id,                // requestId
        bn(1000),          // amount
        []                 // oracleData
      );

      expect(payCost).to.eq.BN(0);
    });
    it('Base', async () => {
      const loanAmount = bn(1000);
      const amountToPaid = bn(100);
      const id = await lendLoan(await requestLoan(loanAmount));

      const payCost = await converterRamp.getPayCostWithFee.call(
        converter.address, // converter
        testToken.address, // fromToken
        id, // requestId
        amountToPaid, // amount
        [] // oracleData
      );

      expect(payCost).to.eq.BN(await withFee(amountToPaid));
    });
    it('With oracle', async () => {
      const loanAmount = bn(1000);
      const amountToPaid = bn(100);
      const id = await lendLoan(await requestLoan(loanAmount, oracle.address));

      const oracleData = await oracle.encodeRate(toETH(), toETH().mul(bn(2)));

      const payCost = await converterRamp.getPayCostWithFee.call(
        converter.address, // converter
        testToken.address, // fromToken
        id, // requestId
        amountToPaid, // amount
        oracleData // oracleData
      );

      expect(payCost).to.eq.BN((await withFee(amountToPaid.div(bn(2)))));
    });
    it('Try pay more', async () => {
      const loanAmount = bn(1000);
      const amountToPaid = bn(10000);
      const id = await lendLoan(await requestLoan(loanAmount, oracle.address));

      const oracleData = await oracle.encodeRate(toETH(), toETH().mul(bn(2)));

      const payCost = await converterRamp.getPayCostWithFee.call(
        converter.address, // converter
        testToken.address, // fromToken
        id, // requestId
        amountToPaid, // amount
        oracleData // oracleData
      );

      expect(payCost).to.eq.BN((await withFee(loanAmount.div(bn(2)))));
    });
  });
});
