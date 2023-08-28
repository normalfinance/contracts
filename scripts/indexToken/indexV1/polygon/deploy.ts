import { ethers, run } from "hardhat";

async function main() {
  const IndexToken = await ethers.getContractFactory("IndexToken");
  const token = await IndexToken.deploy();
  await token.deployed();
  console.log("IndexToken deployed at: ", token.address);

  await run(`verify:verify`, {
    address: token.address,
    constructorArguments: [],
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
