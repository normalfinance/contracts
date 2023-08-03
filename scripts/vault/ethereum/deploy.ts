import { formatBytes32String } from "ethers/lib/utils";
import { ethers, run } from "hardhat";

const ETHEREUM_VAULT_PAUSER_ADDRESS =
  process.env.ETHEREUM_VAULT_PAUSER_ADDRESS || "";
const ETHEREUM_VAULT_FEE_CONTROLLER_ADDRESS =
  process.env.ETHEREUM_VAULT_FEE_CONTROLLER_ADDRESS || "";
const ETHEREUM_INDEX_TOKEN_ADDRESS =
  process.env.ETHEREUM_INDEX_TOKEN_ADDRESS || "";

async function main() {
  const Vault = await ethers.getContractFactory("Vault");
  const vault = await Vault.deploy();
  await vault.deployed();
  console.log("Vault deployed at: ", vault.address);

  await run(`verify:verify`, {
    address: vault.address,
    constructorArguments: [],
  });

  await vault.initialize(
    ETHEREUM_VAULT_PAUSER_ADDRESS,
    ETHEREUM_VAULT_FEE_CONTROLLER_ADDRESS,
    ETHEREUM_INDEX_TOKEN_ADDRESS,
    50,
    [
      formatBytes32String("WBTC"),
      formatBytes32String("ETH"),
      formatBytes32String("SHIB"),
      formatBytes32String("LINK"),
      formatBytes32String("UNI"),
      formatBytes32String("LDO"),
      formatBytes32String("AAVE"),
    ],
    [
      "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599",
      "0x0", // TODO: unable to locate Ethereum ETH address
      "00x95ad61b0a150d79219dcf64e1e6cc01f0b64c4cex0",
      "0x514910771af9ca656af840dff83e8264ecf986ca",
      "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984",
      "0x5a98fcbea516cf06857215779fd812ca3bef1b32",
      "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9",
    ]
  );
  console.log("Vault initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
