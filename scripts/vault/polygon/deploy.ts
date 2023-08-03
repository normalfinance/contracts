import { formatBytes32String } from "ethers/lib/utils";
import { ethers, run } from "hardhat";

const POLYGON_VAULT_PAUSER_ADDRESS =
  process.env.POLYGON_VAULT_PAUSER_ADDRESS || "";
const POLYGON_VAULT_FEE_CONTROLLER_ADDRESS =
  process.env.POLYGON_VAULT_FEE_CONTROLLER_ADDRESS || "";
const POLYGON_INDEX_TOKEN_ADDRESS =
  process.env.POLYGON_INDEX_TOKEN_ADDRESS || "";

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
    POLYGON_VAULT_PAUSER_ADDRESS,
    POLYGON_VAULT_FEE_CONTROLLER_ADDRESS,
    POLYGON_INDEX_TOKEN_ADDRESS,
    50,
    [formatBytes32String("MATIC")],
    ["0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0"] // TODO: this is Ethereum address, unsure on Polygon address
  );
  console.log("Vault initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
