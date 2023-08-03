import { formatBytes32String } from "ethers/lib/utils";
import { ethers, run } from "hardhat";

const ARBITRUM_VAULT_PAUSER_ADDRESS =
  process.env.ARBITRUM_VAULT_PAUSER_ADDRESS || "";
const ARBITRUM_VAULT_FEE_CONTROLLER_ADDRESS =
  process.env.ARBITRUM_VAULT_FEE_CONTROLLER_ADDRESS || "";
const ARBITRUM_INDEX_TOKEN_ADDRESS =
  process.env.ARBITRUM_INDEX_TOKEN_ADDRESS || "";

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
    ARBITRUM_VAULT_PAUSER_ADDRESS,
    ARBITRUM_VAULT_FEE_CONTROLLER_ADDRESS,
    ARBITRUM_INDEX_TOKEN_ADDRESS,
    50,
    [formatBytes32String("ARB")],
    ["0x912CE59144191C1204E64559FE8253a0e49E6548"]
  );
  console.log("Vault initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
