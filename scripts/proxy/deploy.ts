import { ethers, run } from "hardhat";

const INDEX_TOKEN_ADDRESS = process.env.INDEX_TOKEN_ADDRESS || "";
const VAULT_ADDRESS = process.env.VAULT_ADDRESS || "";

async function main() {
  const Proxy = await ethers.getContractFactory("Proxy");
  const proxy = await Proxy.deploy();
  await proxy.deployed();
  console.log("Proxy deployed at: ", proxy.address);

  await run(`verify:verify`, {
    address: proxy.address,
    constructorArguments: [],
  });

  await proxy.initialize(INDEX_TOKEN_ADDRESS, VAULT_ADDRESS);
  console.log("Proxy initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
