const UniswapProxy = artifacts.require('./proxy/UniswapProxy.sol');
const UniswapFactoryMock = artifacts.require('./mock/UniswapFactoryMock.sol');
const UniswapExchangeMock = artifacts.require('./mock/UniswapExchangeMock.sol');

const TestTokenMock = artifacts.require('./mock/TestTokenMock.sol');

const ConverterRamp = artifacts.require('./ConverterRamp.sol');

const TestModel = artifacts.require('./mock/diaspore/TestModel.sol');
const TestDebtEngine = artifacts.require('./mock/diaspore/TestDebtEngine.sol');
const TestLoanManager = artifacts.require('./mock/diaspore/TestLoanManager.sol');
const TestRateOracle = artifacts.require('./utils/test/TestRateOracle.sol');

const { BN } = require('openzeppelin-test-helpers');
const Helper = require('./helper/Helper.js');
const { expect } = require('chai');


contract('ConverterRamp', function (accounts) {

    // diaspore
    let debtEngine;
    let loanManager;
    let model;

    // converter
    let converterRamp;

    // uniswap converter
    let uniswapExchangeMock;
    let uniswapFactoryMock;
    let uniswapProxy;

    // oracle
    let oracle;

    // tokens
    let simpleTestToken;
    let simpleDestToken;

    // accounts
    const owner = accounts[0];
    const borrower = accounts[1];
    const lender = accounts[2];
    const payer = accounts[3];
    const signer = accounts[4];

    const INITIAL_BALANCE = new BN(2).pow(new BN(250))

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
        simpleTestToken = await TestTokenMock.new('Test token', 'TEST', 18, { from: owner });
        await simpleTestToken.mint(borrower, INITIAL_BALANCE);
        await simpleTestToken.mint(lender, INITIAL_BALANCE);
        await simpleTestToken.mint(payer, INITIAL_BALANCE);
        await simpleTestToken.mint(signer, INITIAL_BALANCE);

        // Deploy simple dest token
        simpleDestToken = await TestTokenMock.new('Dest token', 'DEST', 18, { from: owner });
        await simpleDestToken.mint(lender, INITIAL_BALANCE);

        converterRamp = await ConverterRamp.new({ from: owner });

        // Deploy uniswap
        uniswapExchangeMock = await UniswapExchangeMock.new(simpleDestToken.address, simpleTestToken.address, { from: owner });
        await simpleDestToken.mint(uniswapExchangeMock.address, INITIAL_BALANCE); // add liquity.
        await simpleTestToken.mint(uniswapExchangeMock.address, INITIAL_BALANCE); // add liquity.
        uniswapFactoryMock = await UniswapFactoryMock.new(uniswapExchangeMock.address, { from: owner });
        uniswapProxy = await UniswapProxy.new(uniswapFactoryMock.address, { from: owner })

        // Deploy Diaspore
        debtEngine = await TestDebtEngine.new(simpleTestToken.address, { from: owner });
        loanManager = await TestLoanManager.new(debtEngine.address, { from: owner });
        model = await TestModel.new();

        // Deploy oracle
        oracle = await TestRateOracle.new();


    });

    it('Should lend and pay using the ramp (uniswap)', async () => {
        
        // Deploy diaspore and request lend
        const salt = new BN(1);
        const amount = new BN(8);
        const expiration = (await Helper.getBlockTime()) + 1000;
        const loanData = await model.encodeData(amount, expiration);

        const id = await calcId(
            amount,
            borrower,
            borrower,
            model.address,
            oracle.address,
            salt,
            expiration,
            loanData
        );


        const Requested = await Helper.toEvent(
            loanManager.requestLoan(
                amount,         // Amount
                model.address,     // Model
                oracle.address,    // Oracle
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

        assert.equal(await loanManager.getAmount(loanId), 8);

        const tokens = new BN('1');
        const equivalent = new BN('1');
        
        await simpleDestToken.approve(converterRamp.address, -1, { from: lender });
        const oracleData = await oracle.encodeRate(tokens, equivalent);

                
        await converterRamp.lend(
            uniswapProxy.address,
            simpleDestToken.address,
            loanManager.address,
            Helper.address0x,
            debtEngine.address,
            loanId,
            oracleData,
            [],
            [],
            { from: lender }
        )
        
        expect(await simpleDestToken.balanceOf(converterRamp.address)).to.be.bignumber.equal(new BN(0));
        expect(await simpleTestToken.balanceOf(converterRamp.address)).to.be.bignumber.equal(new BN(0));
       
        /* assert.equal(await loanManager.ownerOf(loanId), lender);

       /* const payAmount = new BN(333);
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
