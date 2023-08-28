import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-truffle5";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-interface-generator";

const walletUtils = require("./walletUtils");

dotenv.config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  solidity: {
    compilers: [
      {
        version: "0.8.19",
        settings: {
          optimizer: { enabled: true, runs: 800 },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      chainId: 31337,
      accounts: {
        accountsBalance: "10000000000000000000000000",
        //   mnemonic: MNEMONIC,
      },
      allowUnlimitedContractSize: false,
      blockGasLimit: 100000000000000,
    },
    ganache: {
      chainId: 1337,
      url: "http://localhost:8545",
      blockGasLimit: 100000000000000,
      accounts: {
        mnemonic:
          "embark grab raccoon buzz success hint accuse shell hint vivid milk insect",
        path: "m/44'/60'/0'/0",
        initialIndex: 0,
        count: 20,
      },
    },

    // ETHEREUM
    eth_mainnet: {
      chainId: 1,
      url: process.env.ETH_MAINNET_URL || "",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    eth_goerli: {
      chainId: 5,
      url: process.env.ETH_GOERLI_URL || "",
      accounts:
        process.env.DEPLOYER_PRIVATE_KEY !== undefined
          ? [process.env.DEPLOYER_PRIVATE_KEY]
          : walletUtils.makeKeyList(),
    },
    eth_sepolia: {
      chainId: 11155111,
      url: process.env.ETH_SEPOLIA_URL || "",
      accounts:
        process.env.DEPLOYER_PRIVATE_KEY !== undefined
          ? [process.env.DEPLOYER_PRIVATE_KEY]
          : walletUtils.makeKeyList(),
    },

    // POLYGON
    polygon_mainnet: {
      chainId: 137,
      url: process.env.POLYGON_URL || "",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    polygon_mumbai: {
      chainId: 80001,
      url: process.env.POLYGON_MUMBAI_URL || "",
      accounts:
        process.env.DEPLOYER_PRIVATE_KEY !== undefined
          ? [process.env.DEPLOYER_PRIVATE_KEY]
          : walletUtils.makeKeyList(),
    },

    // BINANCE SMART CHAIN (BSC)
    bsc_mainnet: {
      chainId: 56,
      url: process.env.BSC_MAINNET_URL || "",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    bnb_testnet: {
      chainId: 97,
      url: process.env.BSC_TESTNET_URL || "",
      accounts:
        process.env.DEPLOYER_PRIVATE_KEY !== undefined
          ? [process.env.DEPLOYER_PRIVATE_KEY]
          : walletUtils.makeKeyList(),
    },

    // AVALANCHE
    avalanche_mainnet: {
      chainId: 43114,
      url: process.env.AVALANCHE_MAINNET_URL || "",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    avalanche_fuji: {
      chainId: 43113,
      url: process.env.AVALANCHE_FUJI_URL || "",
      accounts:
        process.env.DEPLOYER_PRIVATE_KEY !== undefined
          ? [process.env.DEPLOYER_PRIVATE_KEY]
          : walletUtils.makeKeyList(),
    },

    // ARBITRUM
    arbitrum_mainnet: {
      chainId: 42161,
      url: process.env.ARBITRUM_MAINNET_URL || "",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    arbitrum_goerli: {
      chainId: 421613,
      url: process.env.ARBITRUM_GOERLI_URL || "",
      accounts:
        process.env.DEPLOYER_PRIVATE_KEY !== undefined
          ? [process.env.DEPLOYER_PRIVATE_KEY]
          : walletUtils.makeKeyList(),
    },

    // OPTIMISM
    optimism_mainnet: {
      chainId: 10,
      url: process.env.OPTIMISM_MAINNET_URL || "",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    optimism_goerli: {
      chainId: 420,
      url: process.env.OPTIMISM_GOERLI_URL || "",
      accounts:
        process.env.DEPLOYER_PRIVATE_KEY !== undefined
          ? [process.env.DEPLOYER_PRIVATE_KEY]
          : walletUtils.makeKeyList(),
    },

    // HEDERA
    hedera_mainnet: {
      chainId: 295,
      url: process.env.HEDERA_MAINNET_URL || "",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    hedera_testnet: {
      chainId: 296,
      url: process.env.HEDERA_TESTNET_URL || "",
      accounts:
        process.env.DEPLOYER_PRIVATE_KEY !== undefined
          ? [process.env.DEPLOYER_PRIVATE_KEY]
          : walletUtils.makeKeyList(),
      blockGasLimit: 500000,
    },

    // FILECOIN
    filecoin_mainnet: {
      chainId: 314,
      url: process.env.FILECOIN_MAINNET_URL || "",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    filecoin_calibration: {
      chainId: 314159,
      url: process.env.FILECOIN_CALIBRATION_URL || "",
      accounts:
        process.env.DEPLOYER_PRIVATE_KEY !== undefined
          ? [process.env.DEPLOYER_PRIVATE_KEY]
          : walletUtils.makeKeyList(),
    },
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
    excludeContracts: ["test/"],
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      goerli: process.env.ETHERSCAN_API_KEY || "",
      polygonMumbai: process.env.POLYGONSCAN_API_KEY || "",
      polygon: process.env.POLYGONSCAN_API_KEY || "",
      bscTestnet: process.env.BSCSCAN_API_KEY || "",
      bsc: process.env.BSCSCAN_API_KEY || "",
      avalancheFujiTestnet: process.env.AVALANCHE_API_KEY || "",
      avalanche: process.env.AVALANCHE_API_KEY || "",
      arbitrumGoerli: process.env.ARBITRUM_API_KEY || "",
      arbitrumOne: process.env.ARBITRUM_API_KEY || "",
      optimisticGoerli: process.env.OPTIMISTIC_API_KEY || "",
      optimisticEthereum: process.env.OPTIMISTIC_API_KEY || "",
      hederaTestnet: process.env.HEDERA_API_KEY || "",
      hedera: process.env.HEDERA_API_KEY || "",
      filecoinTestnet: process.env.FILECOIN_API_KEY || "",
      filecoin: process.env.FILECOIN_API_KEY || "",
    },
    customChains: [
      {
        network: "filecoin-calibration",
        chainId: 314159,
        urls: {
          apiURL: "",
          browserURL: "",
        },
      },
    ],
  },
};

export default config;
