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

  await token.initialize(
    "NormalToken",
    "NORM",
    "0x7D504D497b0ca5386F640aDeA2bb86441462d109",
    "0x0591C25ebd0580E0d4F27A82Fc2e24E7489CB5e0"
  );
  console.log("IndexToken initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
