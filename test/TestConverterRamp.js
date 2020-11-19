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
  tryCatchRevert,
  toEvents,
} = require('./common/helper.js');

const ETH_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
const MAX_UINT256 = bn(2).pow(bn(256)).sub(bn(1));
const MAX_UINT64 = bn(2).pow(bn(64)).sub(bn(1));

contract('ConverterRamp', function (accounts) {
  const owner = accounts[1];
  const borrower = accounts[2];
  const lender = accounts[3];
  const payer = accounts[4];
  const notOwner = accounts[5];
  const burner = accounts[6];

  let engToken;
  let testToken;
  let debtEngine;
  let loanManager;
  let model;
  let oracle;
  let ramp;
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
    const salt = new Date().getTime();

    const id = await loanManager.calcId(
      amount,
      borrower,
      borrower,
      model.address,
      oracle,
      address0x,
      salt,
      expiration,
      data,
    );

    await loanManager.requestLoan(
      amount,
      model.address,
      oracle,
      borrower,
      address0x,
      salt,
      expiration,
      data,
      { from: borrower },
    );

    return id;
  }

  async function lendLoan (id, oracleData = []) {
    if (await loanManager.getOracle(id) !== address0x)
      oracleData = await oracle.encodeRate(toETH(), toETH());

    await engToken.setBalance(lender, bn(2).pow(bn(128)));
    await engToken.approve(loanManager.address, MAX_UINT256, { from: lender });

    await loanManager.lend(
      id,
      oracleData,
      address0x,
      0,
      [],
      [],
      { from: lender },
    );

    return id;
  }

  before('Deploy RCN contracts', async () => {
    // Deploy DEST and TEST tokens
    engToken = await TestToken.new();
    testToken = await TestToken.new();

    // Deploy RCN mini-ecosystem
    debtEngine = await TestDebtEngine.new(engToken.address, burner, 100, { from: owner });
    loanManager = await TestLoanManager.new(debtEngine.address);
    model = await TestModel.new();
    await model.setEngine(debtEngine.address);
    oracle = await TestRateOracle.new();
    converter = await TestConverter.new();
    cosigner = await TestCosigner.new();

    // Deploy converter ramp
    ramp = await ConverterRamp.new(loanManager.address, { from: owner });
  });

  it('Check the debtEngine, loanManager and debtEngineToken', async () => {
    const ramp = await ConverterRamp.new(loanManager.address);

    assert.equal(await ramp.debtEngine(), debtEngine.address);
    assert.equal(await ramp.loanManager(), loanManager.address);
    assert.equal(await ramp.debtEngineToken(), await debtEngine.token());
  });
  it('ETH_ADDRESS', async () => {
    assert.equal(await ramp.ETH_ADDRESS(), ETH_ADDRESS);
  });
  it('Try send eth to ramp contract', async () => {
    await tryCatchRevert(
      () => web3.eth.sendTransaction({
        from: owner,
        to: ramp.address,
        value: 1,
      }),
      'receive: send eth rejected'
    );
  });
  it('Function emergencyWithdraw', async () => {
    let prevRampBal = await engToken.balanceOf(ramp.address);
    let prevToBal = await engToken.balanceOf(notOwner);

    await ramp.emergencyWithdraw(
      engToken.address,
      notOwner,
      0,
      { from: owner }
    );

    expect(await engToken.balanceOf(ramp.address)).to.eq.BN(prevRampBal);
    expect(await engToken.balanceOf(notOwner)).to.eq.BN(prevToBal);

    const amount = bn(1);
    await engToken.setBalance(ramp.address, amount);

    prevRampBal = await engToken.balanceOf(ramp.address);
    prevToBal = await engToken.balanceOf(notOwner);

    await ramp.emergencyWithdraw(
      engToken.address,
      notOwner,
      amount,
      { from: owner }
    );

    expect(await engToken.balanceOf(ramp.address)).to.eq.BN(prevRampBal.sub(amount));
    expect(await engToken.balanceOf(notOwner)).to.eq.BN(prevToBal.add(amount));
  });
  describe('Functions onlyOwner', async function () {
    it('Try redeem an entry without being the owner', async function () {
      await tryCatchRevert(
        () => ramp.emergencyWithdraw(
          address0x,
          address0x,
          0,
          { from: notOwner }
        ),
        'The owner should be the sender'
      );
    });
  });
  describe('Function getLendCost', () => {
    it('Base', async () => {
      const loanAmount = bn(1000);
      const id = await requestLoan(loanAmount);

      const lendCost = await ramp.getLendCost.call(
        converter.address, // converter
        testToken.address, // fromToken
        address0x, // cosigner
        id, // requestId
        [], // oracleData
        [] // cosignerData
      );

      expect(lendCost).to.eq.BN(loanAmount);
    });
    it('With cosigner cost', async () => {
      const loanAmount = bn(1000);
      const cosignerCost = bn(1234);
      const id = await requestLoan(loanAmount);

      await cosigner.setCustomData(id, cosignerCost);

      const lendCost = await ramp.getLendCost.call(
        converter.address, // converter
        testToken.address, // fromToken
        cosigner.address, // cosigner
        id, // requestId
        [], // oracleData
        [] // cosignerData
      );

      expect(lendCost).to.eq.BN(loanAmount.add(cosignerCost));
    });
    it('With cosigner cost and oracle', async () => {
      const loanAmount = bn(1000);
      const cosignerCost = bn(1234);
      const id = await requestLoan(loanAmount, oracle.address);

      const oracleData = await oracle.encodeRate(toETH(), toETH().mul(bn(2)));
      await cosigner.setCustomData(id, cosignerCost);

      const lendCost = await ramp.getLendCost.call(
        converter.address, // converter
        testToken.address, // fromToken
        cosigner.address, // cosigner
        id, // requestId
        oracleData, // oracleData
        [] // cosignerData
      );

      expect(lendCost).to.eq.BN(loanAmount.add(cosignerCost).div(bn(2)));
    });
  });
  describe('Function getPayCostWithFee', () => {
    it('Loan without lend', async () => {
      const loanAmount = bn(1000);
      const id = await requestLoan(loanAmount);

      const payCost = await ramp.getPayCostWithFee.call(
        converter.address, // converter
        testToken.address, // fromToken
        id, // requestId
        bn(1000), // amount
        [] // oracleData
      );

      expect(payCost).to.eq.BN(0);
    });
    it('Base', async () => {
      const loanAmount = bn(1000);
      const amountToPaid = bn(100);
      const id = await lendLoan(await requestLoan(loanAmount));

      const payCost = await ramp.getPayCostWithFee.call(
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

      const payCost = await ramp.getPayCostWithFee.call(
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

      const payCost = await ramp.getPayCostWithFee.call(
        converter.address, // converter
        testToken.address, // fromToken
        id, // requestId
        amountToPaid, // amount
        oracleData // oracleData
      );

      expect(payCost).to.eq.BN((await withFee(loanAmount.div(bn(2)))));
    });
  });
  describe('Function lend', () => {
    it('Lend a loan', async () => {
      const loanAmount = bn(1000);
      const id = await requestLoan(loanAmount);

      await converter.setCustomData(0, loanAmount);

      await engToken.setBalance(converter.address, loanAmount);

      await testToken.setBalance(lender, loanAmount);
      await testToken.approve(ramp.address, loanAmount, { from: lender });

      const prevLenderBalEng = await engToken.balanceOf(lender);
      const prevLenderBalTest = await testToken.balanceOf(lender);

      const prevConverterBalEng = await engToken.balanceOf(converter.address);
      const prevConverterBalTest = await testToken.balanceOf(converter.address);

      await ramp.lend(
        converter.address, // converter
        testToken.address, // fromToken
        loanAmount, // maxSpend
        address0x, // cosigner
        0, // cosignerLimitCost
        id, // requestId
        [], // oracleData
        [], // cosignerData
        [], // callbackData
        { from: lender }
      );

      expect(await engToken.balanceOf(lender)).to.eq.BN(prevLenderBalEng);
      expect(await testToken.balanceOf(lender)).to.eq.BN(prevLenderBalTest);

      expect(await engToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalEng.sub(loanAmount));
      expect(await testToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalTest);

      assert.equal(await debtEngine.ownerOf(id), lender);
    });
    it('Lend a loan with oracle', async () => {
      const loanAmount = bn(1000);
      const id = await requestLoan(loanAmount, oracle.address);
      const tokens = toETH();
      const equivalent = toETH().mul(bn(2));
      const oracleData = await oracle.encodeRate(tokens, equivalent);

      await converter.setCustomData(0, loanAmount);

      await engToken.setBalance(converter.address, loanAmount);

      await testToken.setBalance(lender, loanAmount);
      await testToken.approve(ramp.address, loanAmount, { from: lender });

      const prevLenderBalEng = await engToken.balanceOf(lender);
      const prevLenderBalTest = await testToken.balanceOf(lender);

      const prevConverterBalEng = await engToken.balanceOf(converter.address);
      const prevConverterBalTest = await testToken.balanceOf(converter.address);

      const ReadedOracle = await toEvents(
        ramp.lend(
          converter.address, // converter
          testToken.address, // fromToken
          loanAmount, // maxSpend
          address0x, // cosigner
          0, // cosignerLimitCost
          id, // requestId
          oracleData, // oracleData
          [], // cosignerData
          [], // callbackData
          { from: lender }
        ),
        'ReadedOracle'
      );

      assert.equal(ReadedOracle[0]._oracle, oracle.address);
      expect(ReadedOracle[0]._tokens).to.eq.BN(tokens);
      expect(ReadedOracle[0]._equivalent).to.eq.BN(equivalent);

      assert.equal(ReadedOracle[1]._oracle, oracle.address);
      expect(ReadedOracle[1]._tokens).to.eq.BN(tokens);
      expect(ReadedOracle[1]._equivalent).to.eq.BN(equivalent);

      expect(await engToken.balanceOf(lender)).to.eq.BN(prevLenderBalEng);
      expect(await testToken.balanceOf(lender)).to.eq.BN(prevLenderBalTest);

      expect(await engToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalEng.sub(loanAmount));
      expect(await testToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalTest);

      assert.equal(await debtEngine.ownerOf(id), lender);
    });
    it('Lend a loan with oracle and cosigner cost', async () => {
      const loanAmount = bn(1000);
      const cosignerCost = bn(1234);
      const id = await requestLoan(loanAmount, oracle.address);
      const tokens = toETH();
      const equivalent = toETH().mul(bn(2));
      const oracleData = await oracle.encodeRate(tokens, equivalent);

      await cosigner.setCustomData(id, 0);
      await converter.setCustomData(0, loanAmount.add(cosignerCost));

      await engToken.setBalance(converter.address, loanAmount.add(cosignerCost));

      await testToken.setBalance(lender, loanAmount.add(cosignerCost));
      await testToken.approve(ramp.address, loanAmount.add(cosignerCost), { from: lender });

      const prevLenderBalEng = await engToken.balanceOf(lender);
      const prevLenderBalTest = await testToken.balanceOf(lender);

      const prevConverterBalEng = await engToken.balanceOf(converter.address);
      const prevConverterBalTest = await testToken.balanceOf(converter.address);

      const ReadedOracle = await toEvents(
        ramp.lend(
          converter.address, // converter
          testToken.address, // fromToken
          loanAmount, // maxSpend
          cosigner.address, // cosigner
          cosignerCost, // cosignerLimitCost
          id, // requestId
          oracleData, // oracleData
          [], // cosignerData
          [], // callbackData
          { from: lender }
        ),
        'ReadedOracle'
      );

      assert.equal(ReadedOracle[0]._oracle, oracle.address);
      expect(ReadedOracle[0]._tokens).to.eq.BN(tokens);
      expect(ReadedOracle[0]._equivalent).to.eq.BN(equivalent);

      assert.equal(ReadedOracle[1]._oracle, oracle.address);
      expect(ReadedOracle[1]._tokens).to.eq.BN(tokens);
      expect(ReadedOracle[1]._equivalent).to.eq.BN(equivalent);

      expect(await engToken.balanceOf(lender)).to.eq.BN(prevLenderBalEng);
      expect(await testToken.balanceOf(lender)).to.eq.BN(prevLenderBalTest);

      expect(await engToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalEng.sub(loanAmount.add(cosignerCost)));
      expect(await testToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalTest);

      assert.equal(await debtEngine.ownerOf(id), lender);
    });
  });
  describe('Function _pullConvertAndReturnExtra', () => {
    it('Not spent fromToken', async () => {
      const loanAmount = bn(1000);
      const id = await requestLoan(loanAmount);

      await converter.setCustomData(0, loanAmount);

      await engToken.setBalance(converter.address, loanAmount);

      await testToken.setBalance(lender, loanAmount);
      await testToken.approve(ramp.address, loanAmount, { from: lender });

      const prevLenderBalEng = await engToken.balanceOf(lender);
      const prevLenderBalTest = await testToken.balanceOf(lender);

      const prevConverterBalEng = await engToken.balanceOf(converter.address);
      const prevConverterBalTest = await testToken.balanceOf(converter.address);

      await ramp.lend(
        converter.address, // converter
        testToken.address, // fromToken
        loanAmount, // maxSpend
        address0x, // cosigner
        0, // cosignerLimitCost
        id, // requestId
        [], // oracleData
        [], // cosignerData
        [], // callbackData
        { from: lender }
      );

      expect(await engToken.balanceOf(lender)).to.eq.BN(prevLenderBalEng);
      expect(await testToken.balanceOf(lender)).to.eq.BN(prevLenderBalTest);

      expect(await engToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalEng.sub(loanAmount));
      expect(await testToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalTest);
    });
    it('Spent fromToken', async () => {
      const loanAmount = bn(1000);
      const id = await requestLoan(loanAmount);

      await converter.setCustomData(loanAmount.div(bn(2)), loanAmount);

      await engToken.setBalance(converter.address, loanAmount);

      await testToken.setBalance(lender, loanAmount);
      await testToken.approve(ramp.address, loanAmount, { from: lender });

      const prevLenderBalEng = await engToken.balanceOf(lender);
      const prevLenderBalTest = await testToken.balanceOf(lender);

      const prevConverterBalEng = await engToken.balanceOf(converter.address);
      const prevConverterBalTest = await testToken.balanceOf(converter.address);

      await ramp.lend(
        converter.address, // converter
        testToken.address, // fromToken
        loanAmount, // maxSpend
        address0x, // cosigner
        0, // cosignerLimitCost
        id, // requestId
        [], // oracleData
        [], // cosignerData
        [], // callbackData
        { from: lender }
      );

      expect(await engToken.balanceOf(lender)).to.eq.BN(prevLenderBalEng);
      expect(await testToken.balanceOf(lender)).to.eq.BN(prevLenderBalTest.sub(loanAmount.div(bn(2))));

      expect(await engToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalEng.sub(loanAmount));
      expect(await testToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalTest.add(loanAmount.div(bn(2))));
    });
    it('Spent all fromToken', async () => {
      const loanAmount = bn(1000);
      const id = await requestLoan(loanAmount);

      await converter.setCustomData(loanAmount, loanAmount);

      await engToken.setBalance(converter.address, loanAmount);

      await testToken.setBalance(lender, loanAmount);
      await testToken.approve(ramp.address, loanAmount, { from: lender });

      const prevLenderBalEng = await engToken.balanceOf(lender);
      const prevLenderBalTest = await testToken.balanceOf(lender);

      const prevConverterBalEng = await engToken.balanceOf(converter.address);
      const prevConverterBalTest = await testToken.balanceOf(converter.address);

      await ramp.lend(
        converter.address, // converter
        testToken.address, // fromToken
        loanAmount, // maxSpend
        address0x, // cosigner
        0, // cosignerLimitCost
        id, // requestId
        [], // oracleData
        [], // cosignerData
        [], // callbackData
        { from: lender }
      );

      expect(await engToken.balanceOf(lender)).to.eq.BN(prevLenderBalEng);
      expect(await testToken.balanceOf(lender)).to.eq.BN(prevLenderBalTest.sub(loanAmount));

      expect(await engToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalEng.sub(loanAmount));
      expect(await testToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalTest.add(loanAmount));
    });
  });
  describe('Function _transfer', () => {
    it('Transfer ERC20', async () => {
      const loanAmount = bn(1000);
      const id = await requestLoan(loanAmount);

      await converter.setCustomData(loanAmount.div(bn(2)), loanAmount);

      await engToken.setBalance(converter.address, loanAmount);

      await testToken.setBalance(lender, loanAmount);
      await testToken.approve(ramp.address, loanAmount, { from: lender });

      const prevLenderBalEng = await engToken.balanceOf(lender);
      const prevLenderBalTest = await testToken.balanceOf(lender);

      const prevConverterBalEng = await engToken.balanceOf(converter.address);
      const prevConverterBalTest = await testToken.balanceOf(converter.address);

      await ramp.lend(
        converter.address, // converter
        testToken.address, // fromToken
        loanAmount, // maxSpend
        address0x, // cosigner
        0, // cosignerLimitCost
        id, // requestId
        [], // oracleData
        [], // cosignerData
        [], // callbackData
        { from: lender }
      );

      expect(await engToken.balanceOf(lender)).to.eq.BN(prevLenderBalEng);
      expect(await testToken.balanceOf(lender)).to.eq.BN(prevLenderBalTest.sub(loanAmount.div(bn(2))));

      expect(await engToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalEng.sub(loanAmount));
      expect(await testToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalTest.add(loanAmount.div(bn(2))));
    });
    it('Transfer ETH', async () => {
      const loanAmount = bn(1000);
      const id = await requestLoan(loanAmount);

      await converter.setCustomData(loanAmount.div(bn(2)), loanAmount);

      await engToken.setBalance(converter.address, loanAmount);

      await testToken.setBalance(lender, loanAmount);
      await testToken.approve(ramp.address, loanAmount, { from: lender });

      const prevLenderBalEng = await engToken.balanceOf(lender);
      const prevLenderBalETH = bn(await web3.eth.getBalance(lender));

      const prevConverterBalEng = await engToken.balanceOf(converter.address);
      const prevConverterBalETH = bn(await web3.eth.getBalance(converter.address));

      await ramp.lend(
        converter.address, // converter
        ETH_ADDRESS, // fromToken
        loanAmount, // maxSpend
        address0x, // cosigner
        0, // cosignerLimitCost
        id, // requestId
        [], // oracleData
        [], // cosignerData
        [], // callbackData
        {
          from: lender,
          value: loanAmount,
          gasPrice: 0,
        }
      );

      expect(await engToken.balanceOf(lender)).to.eq.BN(prevLenderBalEng);
      expect(await web3.eth.getBalance(lender)).to.eq.BN(prevLenderBalETH.sub(loanAmount.div(bn(2))));

      expect(await engToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalEng.sub(loanAmount));
      expect(await web3.eth.getBalance(converter.address)).to.eq.BN(prevConverterBalETH.add(loanAmount.div(bn(2))));
    });
  });
  describe('Function _pull', () => {
    it('Try pull ERC20 with msg.value', async () => {
      const loanAmount = bn(1000);
      const id = await requestLoan(loanAmount);

      await converter.setCustomData(loanAmount, loanAmount);

      await engToken.setBalance(converter.address, loanAmount);

      await testToken.setBalance(lender, loanAmount);
      await testToken.approve(ramp.address, loanAmount, { from: lender });

      await tryCatchRevert(
        () => ramp.lend(
          converter.address, // converter
          testToken.address, // fromToken
          loanAmount, // maxSpend
          address0x, // cosigner
          0, // cosignerLimitCost
          id, // requestId
          [], // oracleData
          [], // cosignerData
          [], // callbackData
          {
            from: lender,
            value: 1,
          }
        ),
        '_pull: method is not payable'
      );
    });
    it('Try pull ETH without msg.value', async () => {
      const loanAmount = bn(1000);
      const id = await requestLoan(loanAmount);

      await converter.setCustomData(loanAmount, loanAmount);

      await engToken.setBalance(converter.address, loanAmount);

      await testToken.setBalance(lender, loanAmount);
      await testToken.approve(ramp.address, loanAmount, { from: lender });

      await tryCatchRevert(
        () => ramp.lend(
          converter.address, // converter
          ETH_ADDRESS, // fromToken
          loanAmount, // maxSpend
          address0x, // cosigner
          0, // cosignerLimitCost
          id, // requestId
          [], // oracleData
          [], // cosignerData
          [], // callbackData
          {
            from: lender,
            value: 0,
          }
        ),
        '_pull: sent eth is not enought'
      );
    });
  });
  describe.only('Function pay', () => {
    it('Pay a loan', async () => {
      const id = await lendLoan(await requestLoan(bn(1000)));

      const payAmount = bn(123);
      const totalPayAmount = await withFee(payAmount);

      await converter.setCustomData(totalPayAmount, totalPayAmount);

      await engToken.setBalance(converter.address, totalPayAmount);

      await testToken.setBalance(payer, totalPayAmount);
      await testToken.approve(ramp.address, totalPayAmount, { from: payer });

      const prevPayerBalEng = await engToken.balanceOf(payer);
      const prevPayerBalTest = await testToken.balanceOf(payer);

      const prevConverterBalEng = await engToken.balanceOf(converter.address);
      const prevConverterBalTest = await testToken.balanceOf(converter.address);

      await ramp.pay(
        converter.address, // converter
        testToken.address, // fromToken
        payAmount, // payAmount
        totalPayAmount, // maxSpend
        id, // requestId
        [], // oracleData
        { from: payer }
      );

      expect(await engToken.balanceOf(payer)).to.eq.BN(prevPayerBalEng);
      expect(await testToken.balanceOf(payer)).to.eq.BN(prevPayerBalTest.sub(totalPayAmount));

      expect(await engToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalEng.sub(totalPayAmount));
      expect(await testToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalTest.add(totalPayAmount));

      expect((await debtEngine.debts(id)).balance).to.eq.BN(payAmount);
    });
    it('Pay a loan with oracle', async () => {
      const id = await lendLoan(await requestLoan(bn(1000), oracle.address));
      const payAmount = bn(123);
      const totalPayAmount = await withFee(payAmount);

      const tokens = toETH();
      const equivalent = toETH();
      const oracleData = await oracle.encodeRate(tokens, equivalent);

      await converter.setCustomData(totalPayAmount, totalPayAmount);

      await engToken.setBalance(converter.address, totalPayAmount);

      await testToken.setBalance(payer, totalPayAmount);
      await testToken.approve(ramp.address, totalPayAmount, { from: payer });

      const prevPayerBalEng = await engToken.balanceOf(payer);
      const prevPayerBalTest = await testToken.balanceOf(payer);

      const prevConverterBalEng = await engToken.balanceOf(converter.address);
      const prevConverterBalTest = await testToken.balanceOf(converter.address);

      const ReadedOracle = await toEvents(
        ramp.pay(
          converter.address, // converter
          testToken.address, // fromToken
          payAmount, // payAmount
          totalPayAmount, // maxSpend
          id, // requestId
          oracleData, // oracleData
          { from: payer }
        ),
        'ReadedOracle'
      );

      assert.equal(ReadedOracle._oracle, oracle.address);
      expect(ReadedOracle._tokens).to.eq.BN(tokens);
      expect(ReadedOracle._equivalent).to.eq.BN(equivalent);

      expect(await engToken.balanceOf(payer)).to.eq.BN(prevPayerBalEng);
      expect(await testToken.balanceOf(payer)).to.eq.BN(prevPayerBalTest.sub(totalPayAmount));

      expect(await engToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalEng.sub(totalPayAmount));
      expect(await testToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalTest.add(totalPayAmount));

      expect((await debtEngine.debts(id)).balance).to.eq.BN(payAmount);
    });
    it('Pay a loan', async () => {
      const loanAmount = bn(1000);
      const id = await lendLoan(await requestLoan(loanAmount));

      const payAmount = bn(1234);
      const totalPayAmount = await withFee(loanAmount);

      await converter.setCustomData(totalPayAmount, totalPayAmount);

      await engToken.setBalance(converter.address, totalPayAmount);

      await testToken.setBalance(payer, totalPayAmount);
      await testToken.approve(ramp.address, totalPayAmount, { from: payer });

      const prevPayerBalEng = await engToken.balanceOf(payer);
      const prevPayerBalTest = await testToken.balanceOf(payer);

      const prevConverterBalEng = await engToken.balanceOf(converter.address);
      const prevConverterBalTest = await testToken.balanceOf(converter.address);

      await ramp.pay(
        converter.address, // converter
        testToken.address, // fromToken
        payAmount, // payAmount
        totalPayAmount, // maxSpend
        id, // requestId
        [], // oracleData
        { from: payer }
      );

      expect(await engToken.balanceOf(payer)).to.eq.BN(prevPayerBalEng);
      expect(await testToken.balanceOf(payer)).to.eq.BN(prevPayerBalTest.sub(totalPayAmount));

      expect(await engToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalEng.sub(totalPayAmount));
      expect(await testToken.balanceOf(converter.address)).to.eq.BN(prevConverterBalTest.add(totalPayAmount));

      expect((await debtEngine.debts(id)).balance).to.eq.BN(loanAmount);
    });
  });
});
