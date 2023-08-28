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

  await vault.initialize(50, [], []);
  console.log("Vault initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
