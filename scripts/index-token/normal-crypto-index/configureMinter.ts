import { ethers } from "hardhat";

const masterMinterAddress = process.env.INDEX_TOKEN_MASTER_MINTER_ADDRESS || "";
const minterAddress = process.env.INDEX_TOKEN_MINTER_ADDRESS || "";

async function main() {
  const IndexToken = await ethers.getContractAt("IndexToken", "0x0");

  const masterMinter = await ethers.getSigner(masterMinterAddress);

  await IndexToken.connect(masterMinter).configureMinter(minterAddress, 1000);
  console.log("IndexToken minter configured");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
