import { formatBytes32String } from "ethers/lib/utils";
import { ethers, run } from "hardhat";

const OPTIMISM_VAULT_PAUSER_ADDRESS =
  process.env.OPTIMISM_VAULT_PAUSER_ADDRESS || "";
const OPTIMISM_VAULT_FEE_CONTROLLER_ADDRESS =
  process.env.OPTIMISM_VAULT_FEE_CONTROLLER_ADDRESS || "";
const OPTIMISM_INDEX_TOKEN_ADDRESS =
  process.env.OPTIMISM_INDEX_TOKEN_ADDRESS || "";

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
    OPTIMISM_VAULT_PAUSER_ADDRESS,
    OPTIMISM_VAULT_FEE_CONTROLLER_ADDRESS,
    OPTIMISM_INDEX_TOKEN_ADDRESS,
    50,
    [formatBytes32String("OP")],
    ["0x4200000000000000000000000000000000000042"]
  );
  console.log("Vault initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
