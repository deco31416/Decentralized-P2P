require('dotenv').config()
require('@nomicfoundation/hardhat-toolbox')
require('@nomicfoundation/hardhat-verify')

const BSCSCAN_API_KEY = process.env.BSCSCAN_API_KEY || ''
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY
const OPERATOR_PRIVATE_KEY = process.env.OPERATOR_PRIVATE_KEY
const ADMIN_PRIVATE_KEY = process.env.ADMIN_PRIVATE_KEY
const deploymentAccounts = [DEPLOYER_PRIVATE_KEY, OPERATOR_PRIVATE_KEY, ADMIN_PRIVATE_KEY].filter(Boolean)

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: '0.8.20',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true
    }
  },

  paths: {
    sources: './contracts',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts'
  },

  networks: {
    hardhat: {
      chainId: 31337,
      gas: 12000000,
      blockGasLimit: 12000000,
      allowUnlimitedContractSize: true
    },

    localhost: {
      url: 'http://127.0.0.1:8545',
      chainId: 31337
    },

    bsctestnet: {
      url: process.env.BSC_TESTNET_RPC || 'https://data-seed-prebsc-1-s1.binance.org:8545',
      chainId: 97,
      gasPrice: 10000000000,
      accounts: deploymentAccounts
    },

    bscmainnet: {
      url: process.env.BSC_MAINNET_RPC || 'https://bsc-dataseed1.binance.org',
      chainId: 56,
      gasPrice: 5000000000,
      accounts: deploymentAccounts
    }
  },

  etherscan: {
    apiKey: {
      bscTestnet: BSCSCAN_API_KEY,
      bsc: BSCSCAN_API_KEY
    }
  }
}
