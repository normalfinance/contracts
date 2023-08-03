import { formatBytes32String } from "ethers/lib/utils";
import { ethers, run } from "hardhat";

const BINANCE_VAULT_PAUSER_ADDRESS =
  process.env.BINANCE_VAULT_PAUSER_ADDRESS || "";
const BINANCE_VAULT_FEE_CONTROLLER_ADDRESS =
  process.env.BINANCE_VAULT_FEE_CONTROLLER_ADDRESS || "";
const BINANCE_INDEX_TOKEN_ADDRESS =
  process.env.BINANCE_INDEX_TOKEN_ADDRESS || "";

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
    BINANCE_VAULT_PAUSER_ADDRESS,
    BINANCE_VAULT_FEE_CONTROLLER_ADDRESS,
    BINANCE_INDEX_TOKEN_ADDRESS,
    50,
    [formatBytes32String("BNB")],
    ["0xB8c77482e45F1F44dE1745F52C74426C631bDD52"] // TODO: this is from Etherscan token tracker, cannot find BSC address
  );
  console.log("Vault initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
