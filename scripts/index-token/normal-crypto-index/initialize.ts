import { ethers } from "hardhat";

const masterMinterAddress = process.env.INDEX_TOKEN_MASTER_MINTER_ADDRESS || "";

async function main() {
  const token = await ethers.getContractAt("IndexToken", "0x0");

  await token.initialize("Normal Crypto Index", "NORM", masterMinterAddress);
  console.log("IndexToken initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
