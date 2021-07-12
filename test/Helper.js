const BN = web3.utils.BN;

const expect = require('chai')
  .use(require('bn-chai')(BN))
  .expect;

module.exports.expect = expect;

module.exports.bn = (number) => {
  return web3.utils.toBN(number);
};

module.exports.ETH_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
module.exports.MAX_UINT64 = this.bn(2).pow(this.bn(64)).sub(this.bn(1));

module.exports.toETH = (amount = 1) => {
  return this.bn(web3.utils.toWei(amount.toString()));
};

module.exports.random32 = () => {
  return this.bn(web3.utils.randomHex(32));
};

module.exports.toBytes32 = (source) => {
  source = web3.utils.toHex(source);
  const rl = 64;
  source = source.toString().replace('0x', '');
  if (source.length < rl) {
    const diff = 64 - source.length;
    source = '0'.repeat(diff) + source;
  }
  return '0x' + source;
};

module.exports.balanceSnap = async (token, address, account = '') => {
  const snapBalance = await token.balanceOf(address);
  return {
    requireConstant: async function () {
      expect(
        snapBalance,
        `${account} balance should remain constant`
      ).to.eq.BN(
        await token.balanceOf(address)
      );
    },
    requireIncrease: async function (delta) {
      const realincrease = (await token.balanceOf(address)).sub(snapBalance);
      expect(
        snapBalance.add(delta),
        `${account} should increase by ${delta} - but increased by ${realincrease}`
      ).to.eq.BN(
        await token.balanceOf(address)
      );
    },
    requireDecrease: async function (delta) {
      const realdecrease = snapBalance.sub(await token.balanceOf(address));
      expect(
        snapBalance.sub(delta),
        `${account} should decrease by ${delta} - but decreased by ${realdecrease}`
      ).to.eq.BN(
        await token.balanceOf(address)
      );
    },
    restore: async function () {
      await token.setBalance(address, snapBalance);
    },
  };
};

module.exports.etherSnap = async (address, account = '') => {
  const snapBalance = new BN(await web3.eth.getBalance(address));
  return {
    requireConstant: async function () {
      expect(
        snapBalance,
        `${account} balance should remain constant`
      ).to.eq.BN(
        await web3.eth.getBalance(address)
      );
    },
    requireIncrease: async function (delta) {
      const realincrease = new BN(await web3.eth.getBalance(address)).sub(snapBalance);
      expect(
        snapBalance.add(delta),
        `${account} should increase by ${delta} - but increased by ${realincrease}`
      ).to.eq.BN(
        new BN(await web3.eth.getBalance(address))
      );
    },
    requireDecrease: async function (delta) {
      const realdecrease = snapBalance.sub(new BN(await web3.eth.getBalance(address)));
      expect(
        snapBalance.sub(delta),
        `${account} should decrease by ${delta} - but decreased by ${realdecrease}`
      ).to.eq.BN(
        new BN(await web3.eth.getBalance(address))
      );
    },
  };
};
