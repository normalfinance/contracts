import { ethers, run } from "hardhat";

async function main() {
  const Vault = await ethers.getContractFactory("Vault");
  const vault = await Vault.deploy("0x0", 50, "0x0", "0x0");
  await vault.deployed();
  console.log("Vault deployed at: ", vault.address);

  await run(`verify:verify`, {
    address: vault.address,
    constructorArguments: ["0x0", 50, "0x0", "0x0"],
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
