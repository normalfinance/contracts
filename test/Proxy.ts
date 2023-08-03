import { expect } from "chai";
import { ethers } from "hardhat";
import {
  Proxy,
  IndexToken,
  IndexToken__factory,
  Vault,
  Vault__factory,
} from "../typechain";
import { parseEther } from "ethers/lib/utils";

export async function deployIndexToken(
  provider = ethers.provider
): Promise<IndexToken> {
  const itf = await (await ethers.getContractFactory("IndexToken")).deploy();
  return IndexToken__factory.connect(itf.address, provider.getSigner());
}

export async function deployVault(provider = ethers.provider): Promise<Vault> {
  const vf = await (await ethers.getContractFactory("Vault")).deploy();
  return Vault__factory.connect(vf.address, provider.getSigner());
}

export const AddressZero = "0x0000000000000000000000000000000000000000";
export const AddressOne = "0x0000000000000000000000000000000000000001";

describe("Proxy tests", function () {
  let proxy: Proxy;
  let vault: Vault;
  let token: IndexToken;

  let owner: any;
  let feeController: any;
  let pauser: any;
  let bob: any;

  let ownerAddress: string;
  let feeControllerAddress: string;
  let pauserAddress: string;
  let bobAddress: string;

  let tx: any;

  before(async () => {
    [owner, pauser, feeController, bob] = await ethers.getSigners();
    token = await deployIndexToken();
    vault = await deployVault();

    ownerAddress = await owner.getAddress();
    feeControllerAddress = feeController.getAddress();
    pauserAddress = await pauser.getAddress();
    bobAddress = await bob.getAddress();

    // Init Token
    await token.initialize("NormalToken", "NORM");
    console.log("Token initialized");

    // Init Vault
    await vault.initialize(
      pauserAddress,
      feeControllerAddress,
      token.address,
      50,
      [],
      []
    );
    console.log("Vault initialized");

    // Deploy Proxy
    const Proxy = await ethers.getContractFactory("Proxy");
    proxy = await Proxy.deploy();
    await proxy.deployed();
    console.log("Proxy deployed at: ", proxy.address);

    // Init Proxy
    await proxy.initialize(token.address, vault.address);
    console.log("Vault initialized");
  });

  describe("updateBalances: ", function () {
    it("success if OWNER call", async () => {
      tx = await proxy.connect(owner).updateBalances([], []);
      await tx.wait();

      // expect();
    });

    it("fail if not OWNER call", async () => {
      tx = proxy.connect(bob).updateBalances([], []);
      await expect(tx).to.be.reverted;
    });

    it("fail if uneven arrays", async () => {
      tx = proxy.connect(owner).updateBalances([], []);
      await expect(tx).to.be.reverted;
    });
  });

  describe("batchWithdraw: ", function () {
    it("success if OWNER call", async () => {
      tx = await proxy.connect(owner).batchWithdraw([], [], [], []);
      await tx.wait();

      // expect();
    });

    it("fail if not OWNER call", async () => {
      tx = proxy.connect(bob).batchWithdraw([], [], [], []);
      await expect(tx).to.be.reverted;
    });

    it("fail if uneven arrays", async () => {
      tx = proxy.connect(owner).batchWithdraw([], [], [], []);
      await expect(tx).to.be.reverted;
    });

    it("fail if contains invalid signature", async () => {
      tx = proxy.connect(owner).batchWithdraw([], [], [], []);
      await expect(tx).to.be.reverted;
    });

    // TODO: add fail cases from Vault.withdraw sub-call
  });
});
