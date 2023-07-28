import { ethers, run } from "hardhat";

const wormholeRelayer = process.env.BUNDLER_ADMIN_ADDRESS_DEV || "";

async function main() {
  const Registry = await ethers.getContractFactory("Registry");
  const registry = await Registry.deploy(wormholeRelayer);
  await registry.deployed();
  console.log("Registry deployed at: ", registry.address);

  await run(`verify:verify`, {
    address: registry.address,
    constructorArguments: [wormholeRelayer],
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
