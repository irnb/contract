import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import 'hardhat-abi-exporter'
import * as dotenv from 'dotenv'

dotenv.config({ path: __dirname + '/.env' })

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 20,
      },
      viaIR: true,
    },
  },

  abiExporter: {
    path: './ABI',
    runOnCompile: true,
    clear: true,
    flat: true,
    spacing: 2,
    pretty: true,
  },

  typechain: {
    outDir: "types",
    target: "ethers-v5",
  },

  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },

  gasReporter: {
    enabled: true,
    currency: 'USD',
    coinmarketcap: '10ff6b76-b425-4a67-8878-ac1e33c59407',
  },

  networks: {
    hardhat: {
      blockGasLimit: 100000000,
      gas: 100000000,
    },

    Goerli: {
      url: process.env.GOERLI_URL || '',
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },

    ETH: {
      url: process.env.ETH_URL || '',
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
  },
};

export default config;
