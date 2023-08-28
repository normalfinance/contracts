import { ethers } from "hardhat";

async function main() {
  const vault = await ethers.getContractAt("Vault", "0x0");

  await vault.initialize(50, [], []);
  console.log("Vault initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
