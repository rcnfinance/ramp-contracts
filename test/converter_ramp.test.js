const UniswapProxy = artifacts.require('./proxy/UniswapProxy.sol');
const UniswapFactoryMock = artifacts.require('./mock/UniswapFactoryMock.sol');
const UniswapExchangeMock = artifacts.require('./mock/UniswapExchangeMock.sol');

const TestMock = artifacts.require('./mock/TestMock.sol');

const ConverterRamp = artifacts.require('./ConverterRamp.sol');

const TestModel = artifacts.require('./mock/diaspore/TestModel.sol');
const LoanManager = artifacts.require('./mock/diaspore/LoanManager.sol');
const TestDebtEngine = artifacts.require('./mock/diaspore/TestDebtEngine.sol');
const TestLoanManager = artifacts.require('./mock/diaspore/TestLoanManager.sol');
const TestRateOracle = artifacts.require('./utils/test/TestRateOracle.sol');

const { BN } = require('openzeppelin-test-helpers');
const Helper = require('./helper/Helper.js');


contract('ConverterRamp', function (accounts) {

    let debtEngine;
    let loanManager;
    let model;

    let converterRamp;
    let uniswapProxy;

    // uniswap converter
    let converter;
    let uniswapExchangeMock;
    let uniswapFactoryMock;
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

    async function calcId (_amount, _borrower, _creator, _model, _oracle, _salt, _expiration, _data, _callback = Helper.address0x) {
        const _two = '0x02';
        const controlId = await loanManager.calcId(
            _amount,
            _borrower,
            _creator,
            model.address,
            _oracle,
            _callback,
            _salt,
            _expiration,
            _data
        );

        const controlInternalSalt = await loanManager.buildInternalSalt(
            _amount,
            _borrower,
            _creator,
            _callback,
            _salt,
            _expiration
        );

        const internalSalt = web3.utils.hexToNumberString(
            web3.utils.soliditySha3(
                { t: 'uint128', v: _amount },
                { t: 'address', v: _borrower },
                { t: 'address', v: _creator },
                { t: 'address', v: _callback },
                { t: 'uint256', v: _salt },
                { t: 'uint64', v: _expiration }
            )
        );

        const id = web3.utils.soliditySha3(
            { t: 'uint8', v: _two },
            { t: 'address', v: debtEngine.address },
            { t: 'address', v: loanManager.address },
            { t: 'address', v: model.address },
            { t: 'address', v: _oracle },
            { t: 'uint256', v: internalSalt },
            { t: 'bytes', v: _data }
        );

        assert.equal(internalSalt, controlInternalSalt, 'bug internalSalt');
        assert.equal(id, controlId, 'bug calcId');
        return id;
    }

    before('Deploy tokens, uniswap, converter, ramp and diaspore', async function () {
        
        // Deploy simple test token
        simpleTestToken = await TestMock.new('Test token', 'TEST', 18, { from: owner });
        await simpleTestToken.mint(borrower, INITIAL_BALANCE);
        await simpleTestToken.mint(lender, INITIAL_BALANCE);
        await simpleTestToken.mint(payer, INITIAL_BALANCE);
        await simpleTestToken.mint(signer, INITIAL_BALANCE);

        // Deploy simple dest token
        simpleDestToken = await TestMock.new('Dest token', 'DEST', 18, { from: owner });

        // Deploy ramp
        converterRamp = await ConverterRamp.new({ from: owner });

        // Deploy uniswap
        uniswapExchangeMock = await UniswapExchangeMock.new(simpleTestToken.address, simpleDestToken.address, { from: owner });
        await simpleTestToken.mint(uniswapExchangeMock.address, INITIAL_BALANCE); // add liquity.
        await simpleDestToken.mint(uniswapExchangeMock.address, INITIAL_BALANCE); // add liquity.
        uniswapFactoryMock = await UniswapFactoryMock.new(uniswapExchangeMock.address, { from: owner });
        uniswapProxy = await UniswapProxy.new(uniswapFactoryMock.address, { from: owner })

        // Deploy Ramp
        converterRamp = await ConverterRamp.new()

        // Deploy Diaspore

        debtEngine = await TestDebtEngine.new(simpleTestToken.address, { from: owner });
        loanManager = await TestLoanManager.new(debtEngine.address, { from: owner });
        model = await TestModel.new();
    });

    it('Should lend and pay using the ramp (uniswap)', async () => {
        
        // Deploy diaspore and request lend
        const salt = new BN(1);
        const amount = new BN(1031230);
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

        const Requested = await Helper.toEvent(
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
        console.log(loanId)

        await simpleTestToken.approve(converterRamp.address, amount.mul(new BN(5)), { from: lender });

        /*const lendLoanParams = [
            Helper.toBytes32(rcnEngine.address),
            Helper.toBytes32(loanId),
            Helper.toBytes32(Helper.address0x),
        ];

        const convertParams = [
            new BN(50),
            new BN(0),
            new BN(0),
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

        (await tico.balanceOf(converterRamp.address)).should.be.bignumber.equal(new BN(0));
        (await rcn.balanceOf(converterRamp.address)).should.be.bignumber.equal(new BN(0));
        assert.equal(await rcnEngine.ownerOf(loanId), lender);

        const payAmount = new BN(333);
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
