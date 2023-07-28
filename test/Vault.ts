import { expect } from "chai";
import { ethers } from "hardhat";
import { EntryPoint, EntryPoint__factory, Registry } from "../typechain";
import { BigNumber } from "ethers";
import { keccak256, parseEther, toUtf8Bytes } from "ethers/lib/utils";

export async function deployEntryPoint(
  provider = ethers.provider
): Promise<EntryPoint> {
  const epf = await (await ethers.getContractFactory("EntryPoint")).deploy();
  return EntryPoint__factory.connect(epf.address, provider.getSigner());
}

export const AddressZero = "0x0000000000000000000000000000000000000000";
export const AddressOne = "0x0000000000000000000000000000000000000001";

describe("Bundler tests", function () {
  let vault: Vault;
  let admin: string;
  let accounts: any;
  let tx: any;

  before(async () => {
    accounts = await ethers.getSigners();
    entryPoint = await deployEntryPoint();

    admin = await accounts[0].getAddress();

    // const Bundler = await ethers.getContractFactory("Bundler");
    // bundler = await Bundler.deploy(admin);
    // await bundler.deployed();
    // console.log("Bundler deployed at: ", bundler.address);
  });

  describe("executeBundle: take native tokens out of Smart Account", function () {
    it("success if transfer transactions work", async () => {});

    it("fail if not admin call", async () => {
      tx = bundler
        .connect(accounts[1])
        .executeBundle(
          [bobAddress, aliceAddress, meganAddress],
          [AddressZero, AddressZero, AddressZero],
          [parseEther("0"), parseEther("0"), parseEther("0")],
          [FunctionSelector, FunctionSelector, FunctionSelector]
        );
      await expect(tx).to.be.reverted;
    });
  });
});
