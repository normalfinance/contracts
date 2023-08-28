import { ethers } from "hardhat";

async function main() {
  const token = await ethers.getContractAt(
    "IndexToken",
    "0x46bC08647dC2aCE093f973560908Bd6a4B5adc08"
  );

  await token.initialize(
    "NormalToken",
    "NORM",
    "0x7D504D497b0ca5386F640aDeA2bb86441462d109"
  );
  console.log("IndexToken initialized");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
