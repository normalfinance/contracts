import { formatBytes32String } from "ethers/lib/utils";
import { ethers, run } from "hardhat";

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
