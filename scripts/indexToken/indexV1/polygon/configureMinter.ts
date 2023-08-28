import { ethers } from "hardhat";

async function main() {
  const IndexToken = await ethers.getContractAt(
    "IndexToken",
    "0x46bC08647dC2aCE093f973560908Bd6a4B5adc08"
  );

  const signer = await ethers.getSigner(
    "0x7D504D497b0ca5386F640aDeA2bb86441462d109"
  );

  await IndexToken.connect(signer).configureMinter(
    "0x7D504D497b0ca5386F640aDeA2bb86441462d109",
    1000
  );
  console.log("IndexToken minter configured");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
