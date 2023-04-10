import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-etherscan'
import '@nomiclabs/hardhat-waffle'
import '@openzeppelin/hardhat-upgrades'
import 'dotenv/config'
import 'hardhat-abi-exporter'
import 'hardhat-contract-sizer'
import 'hardhat-deploy'
import 'hardhat-deploy-ethers'
import 'solidity-coverage'
import 'hardhat-gas-reporter'
import { HardhatUserConfig } from 'hardhat/config'
import glob from 'glob'
import path from 'path'

glob.sync('./tasks/**/*.ts').forEach(function (file) {
  require(path.resolve(file))
})

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.13',
        settings: {
          optimizer: {
            enabled: true,
            runs: 60,
          },
        },
      },
    ],
  },
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {},
    fuji: {
      url: 'https://api.avax-test.network/ext/bc/C/rpc',
      chainId: 43113,
      accounts: process.env.DEPLOY_PRIVATE_KEY ? [process.env.DEPLOY_PRIVATE_KEY] : [],
      saveDeployments: true,
    },
    avalanche: {
      url: 'https://api.avax.network/ext/bc/C/rpc',
      chainId: 43114,
      accounts: process.env.DEPLOY_PRIVATE_KEY ? [process.env.DEPLOY_PRIVATE_KEY] : [],
    },
    bscTestnet: {
      url: process.env.BSC_TESTNET_RPC_ENDPOINT ? process.env.BSC_TESTNET_RPC_ENDPOINT : '',
      gasPrice: 20_000_000_000,
      chainId: 97,
      accounts: process.env.BSC_TESTNET_DEPLOYER ? [process.env.BSC_TESTNET_DEPLOYER] : [],
    },
    bsc: {
      url: process.env.BSC_RPC_ENDPOINT ? process.env.BSC_RPC_ENDPOINT : '',
      gasPrice: 5_000_000_000,
      chainId: 56,
      accounts: process.env.BSC_TESTNET_DEPLOYER ? [process.env.BSC_TESTNET_DEPLOYER] : [],
    },
  },
  contractSizer: {
    strict: true,
  },
  namedAccounts: {
    deployer: 0,
  },
  etherscan: {
    apiKey: {
      avalanche: process.env.SNOWTRACE_API_KEY,
      avalancheFujiTestnet: process.env.SNOWTRACE_API_KEY,
      bscTestnet: process.env.BSC_API_KEY,
      bsc: process.env.BSC_API_KEY,
    },
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 25_000_000_000,
    enabled: true,
    outputFile: 'gas-report.txt',
    noColors: true,
  },
}

export default config
