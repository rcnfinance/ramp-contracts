module.exports = {
  compilers: {
    solc: {
      version: '0.6.6',
      docker: false,
      settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        },
        evmVersion: 'istanbul',
      },
    },
  },
  plugins: ['solidity-coverage'],
};
