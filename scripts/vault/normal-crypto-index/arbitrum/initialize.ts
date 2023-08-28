import { formatBytes32String } from "ethers/lib/utils";
import { ethers } from "hardhat";

async function main() {
  const vault = await ethers.getContractAt("Vault", "0x0");

  await vault.initialize(
    50,
    [formatBytes32String("ARB")],
    ["0x912CE59144191C1204E64559FE8253a0e49E6548"]
  );
  console.log("Vault initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
