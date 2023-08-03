import { formatBytes32String } from "ethers/lib/utils";
import { ethers, run } from "hardhat";

const AVALANCHE_VAULT_PAUSER_ADDRESS =
  process.env.AVALANCHE_VAULT_PAUSER_ADDRESS || "";
const AVALANCHE_VAULT_FEE_CONTROLLER_ADDRESS =
  process.env.AVALANCHE_VAULT_FEE_CONTROLLER_ADDRESS || "";
const AVALANCHE_INDEX_TOKEN_ADDRESS =
  process.env.AVALANCHE_INDEX_TOKEN_ADDRESS || "";

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
    AVALANCHE_VAULT_PAUSER_ADDRESS,
    AVALANCHE_VAULT_FEE_CONTROLLER_ADDRESS,
    AVALANCHE_INDEX_TOKEN_ADDRESS,
    50,
    [formatBytes32String("AVAX")],
    ["FvwEAhmxKfeiG8SnEvq42hc6whRyY3EFYAvebMqDNDGCgxN5Z"]
  );
  console.log("Vault initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
