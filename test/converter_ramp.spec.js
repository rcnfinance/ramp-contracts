
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
const expect = require('chai').use(require('bn-chai')(BN)).expect


const ETH = new BN(10).pow(new BN(18));
const ETH_ADDRESS = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
const MAX_UINT256 = new BN(2).pow(new BN(256)).sub(new BN(1));
const MAX_UINT64 = new BN(2).pow(new BN(64)).sub(new BN(1));

contract('ConverterRamp', function (accounts) {
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
    rcnUniswap = await UniswapExchange.at(await uniswapFactory.getExchange(rcnToken.address));
    // Add liquidity 1 RCN => 0.00005 ETH
    const amountEthRcnLiquidity = new BN(40).mul(ETH);                        // 40 ETH
    const amountRcnLiquidity = amountEthRcnLiquidity.mul(new BN(20000));      // 800000 RCN
    await rcnToken.setBalance(accounts[9], amountRcnLiquidity);
    await rcnToken.approve(rcnUniswap.address, amountRcnLiquidity, { from: accounts[9] });
    await rcnUniswap.addLiquidity(
      0,
      amountRcnLiquidity,
      MAX_UINT256,
      {
        value: amountRcnLiquidity,
        from: accounts[9]
      }
    );
    // Create DEST Uniswap
    await uniswapFactory.createExchange(destToken.address);
    destUniswap = await UniswapExchange.at(await uniswapFactory.getExchange(destToken.address));
    // Add liquidity 1 ETH => 200 DEST
    const amountDestLiquidity = new BN(1000000).mul(ETH);                        // 1000000 DEST
    const amountEthDestLiquidity = amountDestLiquidity.div(new BN(200));         // 5000 ETH
    await destToken.setBalance(accounts[9], amountDestLiquidity);
    await destToken.approve(destUniswap.address, amountDestLiquidity, { from: accounts[9] });
    await destUniswap.addLiquidity(
      0,
      amountDestLiquidity,
      MAX_UINT256,
      {
        value: amountEthDestLiquidity,
        from: accounts[9]
      }
    );
    // Create UniswapConverter
    uniswapConverter = await UniswapConverter.new(uniswapFactory.address);
  });
  async function requestLoan(amount, oracle = Helper.address0x) {
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
        from: creator
      }
    );

    return id;
  }
  it("Shoud lend a loan using ETH, sending the exact amount", async () => {
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
      id,                       // Loan ID
      [],                       // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        value: estimated,
        gasPrice: new BN(0)
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it("Shoud lend a loan using ETH, sending extra ETH amount", async () => {
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
      id,                       // Loan ID
      [],                       // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        value: maxSpend,
        gasPrice: new BN(0)
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equal(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it("Shoud lend a loan using another token, sending the exact amount", async () => {
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
      id,                       // Loan ID
      [],                       // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        gasPrice: new BN(0)
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it("Shoud lend a loan using another token, sending extra amount", async () => {
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
      id,                       // Loan ID
      [],                       // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        gasPrice: new BN(0)
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it("Shoud lend a loan with oracle using ETH, sending the exact amount", async () => {
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
      id,                       // Loan ID
      oracleData,               // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        value: estimated,
        gasPrice: new BN(0)
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it("Shoud lend a loan with oracle using ETH, sending extra ETH amount", async () => {
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
      id,                       // Loan ID
      oracleData,               // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        value: maxSpend,
        gasPrice: new BN(0)
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equal(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it("Shoud lend a loan with oracle using another token, sending the exact amount", async () => {
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
      id,                       // Loan ID
      oracleData,               // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        gasPrice: new BN(0)
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
  it("Shoud lend a loan with oracle using another token, sending extra amount", async () => {
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
      id,                       // Loan ID
      oracleData,               // Oracle data
      [],                       // Cosigner data
      [],                       // Callback data
      {
        from: accounts[5],
        gasPrice: new BN(0)
      }
    );

    expect(await debtEngine.ownerOf(id)).to.be.equals(accounts[5]);
    await ethSnap.requireDecrease(estimated);
  });
});

// const UniswapConverter = artifacts.require('./proxy/UniswapConverter.sol');
// const UniswapFactoryMock = artifacts.require('./mock/UniswapFactoryMock.sol');
// const UniswapExchangeMock = artifacts.require('./mock/UniswapExchangeMock.sol');

// const TestTokenMock = artifacts.require('./mock/TestTokenMock.sol');

// const ConverterRamp = artifacts.require('./ConverterRamp.sol');

// const TestModel = artifacts.require('./mock/diaspore/TestModel.sol');
// const TestDebtEngine = artifacts.require('./mock/diaspore/TestDebtEngine.sol');
// const TestLoanManager = artifacts.require('./mock/diaspore/TestLoanManager.sol');
// const TestRateOracle = artifacts.require('./utils/test/TestRateOracle.sol');

// const Helper = require('./common/helper.js');
// const BN = web3.utils.BN;
// const chai = require('chai');
// chai.use(require('chai-bn')(BN));
// const { expect } = require('chai');

// contract('ConverterRamp', function (accounts) {
//   // diaspore
//   let debtEngine;
//   let loanManager;
//   let model;

//   // converter
//   let converterRamp;

//   // oracle
//   let oracle;

//   // tokens
//   let simpleTestToken;
//   let simpleDestToken;

//   // accounts
//   const owner = accounts[0];
//   const borrower = accounts[1];
//   const lender = accounts[2];
//   const payer = accounts[3];

//   const INITIAL_BALANCE = new BN(2).pow(new BN(250));

//   async function calcId (
//     _amount,
//     _borrower,
//     _creator,
//     _model,
//     _oracle,
//     _salt,
//     _expiration,
//     _data,
//     _callback = Helper.address0x
//   ) {
//     const _two = '0x02';
//     const controlId = await loanManager.calcId(
//       _amount,
//       _borrower,
//       _creator,
//       model.address,
//       _oracle,
//       _callback,
//       _salt,
//       _expiration,
//       _data
//     );

//     const controlInternalSalt = await loanManager.buildInternalSalt(
//       _amount,
//       _borrower,
//       _creator,
//       _callback,
//       _salt,
//       _expiration
//     );

//     const internalSalt = web3.utils.hexToNumberString(
//       web3.utils.soliditySha3(
//         { t: 'uint128', v: _amount },
//         { t: 'address', v: _borrower },
//         { t: 'address', v: _creator },
//         { t: 'address', v: _callback },
//         { t: 'uint256', v: _salt },
//         { t: 'uint64', v: _expiration }
//       )
//     );

//     const id = web3.utils.soliditySha3(
//       { t: 'uint8', v: _two },
//       { t: 'address', v: debtEngine.address },
//       { t: 'address', v: loanManager.address },
//       { t: 'address', v: model.address },
//       { t: 'address', v: _oracle },
//       { t: 'uint256', v: internalSalt },
//       { t: 'bytes', v: _data }
//     );

//     assert.equal(internalSalt, controlInternalSalt, 'bug internalSalt');
//     assert.equal(id, controlId, 'bug calcId');
//     return id;
//   }

//   before('Deploy tokens, uniswap, converter, ramp and diaspore', async function () {
//     // Deploy simple test token
//     simpleTestToken = await TestTokenMock.new('Test token', 'TEST', 18, { from: owner });
//     // Deploy simple dest token
//     simpleDestToken = await TestTokenMock.new('Dest token', 'DEST', 18, { from: owner });

//     converterRamp = await ConverterRamp.new({ from: owner });

//     // Deploy Diaspore
//     debtEngine = await TestDebtEngine.new(simpleTestToken.address, { from: owner });
//     loanManager = await TestLoanManager.new(debtEngine.address, { from: owner });
//     model = await TestModel.new();

//     // Deploy oracle
//     oracle = await TestRateOracle.new();
//   });

//   describe('Pay and lend swap token to token', function () {
//     it('Should lend and pay using the ramp', async () => {
//       // Deploy uniswap
//       const uniswapExchangeMock = await UniswapExchangeMock.new(
//         simpleDestToken.address,
//         simpleTestToken.address,
//         { from: owner }
//       );
//       await simpleTestToken.mint(uniswapExchangeMock.address, INITIAL_BALANCE); // add liquity.
//       const uniswapFactoryMock = await UniswapFactoryMock.new(uniswapExchangeMock.address, { from: owner });
//       const UniswapConverter = await UniswapConverter.new(uniswapFactoryMock.address, { from: owner });

//       const amount = new BN(8);
//       // mint simple test token (lender, payer)
//       await simpleDestToken.mint(lender, amount);
//       await simpleDestToken.mint(payer, amount);

//       const salt = new BN(1);
//       const expiration = (await Helper.getBlockTime()) + 1000;
//       const loanData = await model.encodeData(amount, expiration);

//       const id = await calcId(
//         amount,
//         borrower,
//         borrower,
//         model.address,
//         oracle.address,
//         salt,
//         expiration,
//         loanData
//       );

//       const Requested = await Helper.toEvent(
//         loanManager.requestLoan(
//           amount, // Amount
//           model.address, // Model
//           oracle.address, // Oracle
//           borrower, // Borrower
//           Helper.address0x, // Callback
//           salt, // salt
//           expiration, // Expiration
//           loanData, // Loan data
//           { from: borrower } // Creator
//         ),
//         'Requested'
//       );
//       assert.equal(Requested._id, id);
//       const loanId = Helper.toBytes32(id);

//       expect(await loanManager.getAmount(loanId)).to.be.bignumber.equal(amount);

//       const tokens = new BN(1);
//       const equivalent = new BN(1);

//       await simpleDestToken.approve(converterRamp.address, amount, { from: lender });
//       const oracleData = await oracle.encodeRate(tokens, equivalent);

//       await converterRamp.lend(
//         UniswapConverter.address,
//         simpleDestToken.address,
//         loanManager.address,
//         Helper.address0x,
//         debtEngine.address,
//         loanId,
//         oracleData,
//         [],
//         [],
//         { from: lender }
//       );

//       expect(await simpleDestToken.balanceOf(converterRamp.address)).to.be.bignumber.equal(new BN(0));
//       expect(await simpleDestToken.balanceOf(uniswapFactoryMock.address)).to.be.bignumber.equal(new BN(0));
//       expect(await simpleTestToken.balanceOf(UniswapConverter.address)).to.be.bignumber.equal(new BN(0));

//       assert.equal(await loanManager.ownerOf(loanId), lender);

//       await simpleDestToken.approve(converterRamp.address, amount, { from: payer });

//       await converterRamp.pay(
//         UniswapConverter.address,
//         simpleDestToken.address,
//         loanManager.address,
//         debtEngine.address,
//         payer,
//         loanId,
//         oracleData,
//         { from: payer }
//       );

//       expect(await simpleDestToken.balanceOf(converterRamp.address)).to.be.bignumber.equal(new BN(0));
//       expect(await simpleDestToken.balanceOf(uniswapFactoryMock.address)).to.be.bignumber.equal(new BN(0));
//       expect(await simpleTestToken.balanceOf(UniswapConverter.address)).to.be.bignumber.equal(new BN(0));
//     });
//   });

//   describe('Pay and lend swap eth to token', function () {
//     it('Should lend and pay using the ramp', async () => {
//       const ethAddress = await converterRamp.ETH_ADDRESS();

//       // Deploy uniswap
//       const uniswapExchangeMock = await UniswapExchangeMock.new(ethAddress, simpleTestToken.address, { from: owner });
//       await simpleTestToken.mint(uniswapExchangeMock.address, INITIAL_BALANCE); // add liquity.
//       const uniswapFactoryMock = await UniswapFactoryMock.new(uniswapExchangeMock.address, { from: owner });
//       const UniswapConverter = await UniswapConverter.new(uniswapFactoryMock.address, { from: owner });

//       const amount = new BN(8);
//       const salt = new BN(2);
//       const expiration = (await Helper.getBlockTime()) + 1000;
//       const loanData = await model.encodeData(amount, expiration);

//       const id = await calcId(
//         amount,
//         borrower,
//         borrower,
//         model.address,
//         Helper.address0x,
//         salt,
//         expiration,
//         loanData
//       );

//       const Requested = await Helper.toEvent(
//         loanManager.requestLoan(
//           amount, // Amount
//           model.address, // Model
//           Helper.address0x, // Oracle
//           borrower, // Borrower
//           Helper.address0x, // Callback
//           salt, // salt
//           expiration, // Expiration
//           loanData, // Loan data
//           { from: borrower } // Creator
//         ),
//         'Requested'
//       );
//       assert.equal(Requested._id, id);
//       const loanId = Helper.toBytes32(id);

//       const sendEth = await converterRamp.getCost(
//         amount,
//         UniswapConverter.address,
//         ethAddress,
//         simpleTestToken.address
//       );
//       const ethCost = sendEth[1];
//       const surplus = new BN(1000);

//       let prevConverterRampBal = new BN(await web3.eth.getBalance(converterRamp.address));

//       const lendValue = new BN(ethCost).add(surplus);
//       await converterRamp.lend(
//         UniswapConverter.address,
//         ethAddress,
//         loanManager.address,
//         Helper.address0x,
//         debtEngine.address,
//         loanId,
//         [],
//         [],
//         [],
//         {
//           from: lender,
//           value: lendValue,
//         }
//       );

//       expect(new BN(await web3.eth.getBalance(converterRamp.address))).to.be.bignumber.equal(prevConverterRampBal);
//       expect(new BN(await web3.eth.getBalance(uniswapExchangeMock.address))).to.be.bignumber.equal(amount);
//       expect(new BN(await web3.eth.getBalance(uniswapFactoryMock.address))).to.be.bignumber.equal(new BN(0));
//       expect(new BN(await web3.eth.getBalance(UniswapConverter.address))).to.be.bignumber.equal(new BN(0));

//       expect(await simpleTestToken.balanceOf(converterRamp.address)).to.be.bignumber.equal(new BN(0));
//       expect(await simpleTestToken.balanceOf(uniswapFactoryMock.address)).to.be.bignumber.equal(new BN(0));
//       expect(await simpleTestToken.balanceOf(UniswapConverter.address)).to.be.bignumber.equal(new BN(0));
//       assert.equal(await loanManager.ownerOf(loanId), lender);

//       prevConverterRampBal = new BN(await web3.eth.getBalance(converterRamp.address));

//       const payValue = new BN(ethCost).add(surplus);
//       await converterRamp.pay(
//         UniswapConverter.address,
//         ethAddress,
//         loanManager.address,
//         debtEngine.address,
//         payer,
//         loanId,
//         [],
//         {
//           from: payer,
//           value: payValue,
//         }
//       );

//       expect(new BN(await web3.eth.getBalance(converterRamp.address))).to.be.bignumber.equal(prevConverterRampBal);
//       expect(new BN(await web3.eth.getBalance(uniswapExchangeMock.address))).to.be.bignumber.equal(amount.add(amount));
//       expect(new BN(await web3.eth.getBalance(uniswapFactoryMock.address))).to.be.bignumber.equal(new BN(0));
//       expect(new BN(await web3.eth.getBalance(UniswapConverter.address))).to.be.bignumber.equal(new BN(0));

//       expect(await simpleTestToken.balanceOf(converterRamp.address)).to.be.bignumber.equal(new BN(0));
//       expect(await simpleTestToken.balanceOf(uniswapFactoryMock.address)).to.be.bignumber.equal(new BN(0));
//       expect(await simpleTestToken.balanceOf(UniswapConverter.address)).to.be.bignumber.equal(new BN(0));
//     });
//   });
// });
