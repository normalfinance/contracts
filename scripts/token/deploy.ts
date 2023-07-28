import { ethers, run } from "hardhat";

async function main() {
  const NormalToken = await ethers.getContractFactory("NormalToken");
  const token = await NormalToken.deploy();
  await token.deployed();
  console.log("NormalToken deployed at: ", token.address);

  await run(`verify:verify`, {
    address: token.address,
    constructorArguments: [],
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
