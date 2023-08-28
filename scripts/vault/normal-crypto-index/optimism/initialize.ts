import { formatBytes32String } from "ethers/lib/utils";
import { ethers } from "hardhat";

async function main() {
  const vault = await ethers.getContractAt("Vault", "0x0");

  await vault.initialize(
    50,
    [formatBytes32String("OP")],
    ["0x4200000000000000000000000000000000000042"]
  );
  console.log("Vault initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
