const UniswapConverter = artifacts.require('./proxy/UniswapProxy.sol');
const simpleTestToken = artifacts.require('ERC20Mintable');
const simpleDestToken = artifacts.require('ERC20Mintable');

const ConverterRamp = artifacts.require('./ConverterRamp.sol');

const LoanManager = artifacts.require('./diaspore/LoanManager.sol');
const TestModel = artifacts.require('./diaspore/utils/test/TestModel.sol');
const DebtEngine = artifacts.require('./diaspore/DebtEngine.sol');
const TestDebtEngine = artifacts.require('./diaspore/utils/test/TestDebtEngine.sol');
const TestCosigner = artifacts.require('./utils/test/TestCosigner.sol');
const TestRateOracle = artifacts.require('./utils/test/TestRateOracle.sol');


const Helper = require('../Helper.js');
const BigNumber = web3.BigNumber;

require('chai')
    .use(require('chai-bignumber')(BigNumber))
    .should();

function bn (number) {
    if (typeof number != 'string') {
        number = number.toString();
    }
    return new BigNumber(number);
}

function toWei (ether) {
    return bn(ether).mul(bn(10).pow(bn(18)));
}

contract('ConverterRamp', function (accounts) {
    const gasPrice = toWei(1);

    let diasporeEngine;
    let converterRamp;
    let uniswapProxy;

    // uniswap converter
    let converter;
    
    // loan
    let loanId;

    // tokens
    let simpleTestToken;
    let simpleDestToken;

    // accounts
    const owner = accounts[0];
    const borrower = accounts[1];
    const lender = accounts[2];
    const payer = accounts[3];
    const signer = accounts[4];

    const INITIAL_BALANCE = new BN((100 * 10 ** 18).toString());

    before('Deploy Tokens, Bancor, Converter, Ramp', async function () {
        // Deploy simple test token
        simpleTestToken = await ERC20Mintable.new('Test token', 'TEST', 18, from: owner });
        await simpleTestToken.mint(borrower, INITIAL_BALANCE);
        await simpleTestToken.mint(lender, INITIAL_BALANCE);
        await simpleTestToken.mint(payer, INITIAL_BALANCE);
        await simpleTestToken.mint(signer, INITIAL_BALANCE);

        // Deploy simple dest token
        simpleDestToken = await ERC20Mintable.new('Dest token', 'DEST', 18, from: owner });

        
        loanId = id;

        // Deploy ramp
        converterRamp = await ConverterRamp.new({ from: owner });
        // Deploy uniswap
        // TODO:
    });

    it('Should lend and pay using the ramp (Bancor)', async () => {
        
        // Deploy diaspore and request lend
        const salt = bn('1');
        const amount = bn('1031230');
        const expiration = (await Helper.getBlockTime()) + 1000;
        const loanData = await model.encodeData(amount, expiration);

        const id = await calcId(
            amount,
            borrower,
            borrower,
            model.address,
            Helper.address0x,
            salt,
            expiration,
            loanData
        );

        const Requested = await Helper.toEvents(
            loanManager.requestLoan(
                amount,            // Amount
                model.address,     // Model
                Helper.address0x,  // Oracle
                borrower,          // Borrower
                Helper.address0x,  // Callback
                salt,              // salt
                expiration,        // Expiration
                loanData,          // Loan data
                { from: borrower } // Creator
            ),
            'Requested'
        );

        assert.equal(Requested._id, id);
        const loanId = Helper.toBytes32(id)

        await simpleTestToken.approve(converterRamp.address, amount.mul(bn(5)), { from: lender });

        /*const lendLoanParams = [
            Helper.toBytes32(rcnEngine.address),
            Helper.toBytes32(loanId),
            Helper.toBytes32(Helper.address0x),
        ];

        const convertParams = [
            bn(50),
            bn(0),
            bn(0),
        ];

        await converterRamp.lend(
            bancorProxy.address,
            tico.address,
            lendLoanParams,
            [],
            [],
            convertParams,
            { from: lender }
        );

        (await tico.balanceOf(converterRamp.address)).should.be.bignumber.equal(bn(0));
        (await rcn.balanceOf(converterRamp.address)).should.be.bignumber.equal(bn(0));
        assert.equal(await rcnEngine.ownerOf(loanId), lender);

        const payAmount = bn(333);
        await tico.setBalance(lender, payAmount);
        await tico.approve(converterRamp.address, payAmount, { from: payer });

        const payLoanParams = [
            Helper.toBytes32(rcnEngine.address),
            Helper.toBytes32(loanId),
            Helper.toBytes32(toWei(100)),
            Helper.toBytes32(payer),
        ];

        await converterRamp.pay(
            converter.address,
            tico.address,
            payLoanParams,
            [],
            convertParams,
            { from: payer }
        );*/
    });

});
