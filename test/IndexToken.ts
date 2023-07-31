import { expect } from "chai";
import { ethers } from "hardhat";
import { Vault, IndexToken, IndexToken__factory } from "../typechain";
import { parseEther } from "ethers/lib/utils";

export async function deployIndexToken(
  provider = ethers.provider
): Promise<IndexToken> {
  const ntf = await (await ethers.getContractFactory("IndexToken")).deploy();
  return IndexToken__factory.connect(ntf.address, provider.getSigner());
}

export const AddressZero = "0x0000000000000000000000000000000000000000";
export const AddressOne = "0x0000000000000000000000000000000000000001";
export const FunctionSelector = "0x00000000";

describe("Index Token tests", function () {
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

    ownerAddress = await owner.getAddress();
    feeControllerAddress = feeController.getAddress();
    pauserAddress = await pauser.getAddress();
    bobAddress = await bob.getAddress();

    // Init Token
    await token.initialize("NormalToken", "NORM");
    console.log("Token initialized");

    // Deploy Vault
    const Vault = await ethers.getContractFactory("Vault");
    vault = await Vault.deploy();
    await vault.deployed();
    console.log("Vault deployed at: ", vault.address);

    await vault.initialize(
      pauserAddress,
      feeControllerAddress,
      token.address,
      "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419",
      parseEther("0.005"),
      [],
      [],
      []
    );
    console.log("Vault initialized");
  });

  describe("mint: issues new tokens to Index Fund investor", function () {
    it("success if DEFAULT_ADMIN_CALL", async () => {
      const bobBalanceBefore = await token.balanceOf(bobAddress);
      expect(bobBalanceBefore).to.equal(parseEther("0"));

      tx = await token.connect(owner).mint(bobAddress, parseEther("100"));
      await tx.wait();

      expect(await token.balanceOf(bobAddress)).to.equal(
        bobBalanceBefore.add(parseEther("100"))
      );
    });

    it("fail if not DEFAULT_ADMIN_ROLE call", async () => {
      tx = token.connect(bob).mint(bobAddress, 100);
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid to address", async () => {
      tx = token.connect(owner).mint(AddressZero, 100);
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid amount", async () => {
      tx = token.connect(owner).mint(bobAddress, 0);
      await expect(tx).to.be.reverted;
    });

    it("fail if paused", async () => {
      tx = await token.connect(owner).pause();
      await tx.wait();

      tx = token.connect(owner).mint(bobAddress, 100);
      await expect(tx).to.be.reverted;

      // reset
      (await token.connect(owner).unpause()).wait();
      const isPaused = await token.connect(bob).paused();
      expect(isPaused).to.be.false;
    });
  });

  describe("burn: removes tokens from Index Fund investor", function () {
    it("success if ", async () => {
      const bobBalanceBefore = await token.balanceOf(bobAddress);
      expect(bobBalanceBefore).to.equal(parseEther("100"));

      tx = await token.connect(bob).burn(parseEther("100"));
      await tx.wait();

      expect(await token.balanceOf(bobAddress)).to.equal(
        bobBalanceBefore.sub(parseEther("100"))
      );
    });

    it("fail if ERC20: burn from the zero address", async () => {
      tx = token.connect(AddressZero).burn(parseEther("100"));
      await expect(tx).to.be.reverted;
    });

    it("fail if ERC20: burn amount exceeds balance", async () => {
      tx = token.connect(bob).burn(parseEther("10000"));
      await expect(tx).to.be.reverted;
    });
  });

  describe("snapshot: captures balances for use in voting", function () {
    it("success if SNAPSHOT_ROLE call", async () => {
      tx = await token.connect(owner).snapshot();
      await tx.wait();
    });

    it("fail if not SNAPSHOT_ROLE call", async () => {
      tx = token.connect(bob).snapshot();
      await expect(tx).to.be.reverted;
    });
  });

  describe("pause/unpause: temporarily enable/disable functions marked with whenNotPaused", function () {
    it("success if PAUSER_ROLE call", async () => {
      tx = await token.connect(owner).pause();
      await tx.wait();

      let paused = await token.connect(owner).paused();
      console.log("paused: ", paused.toString());
      expect(paused).to.be.true;

      tx = await token.connect(owner).unpause();
      await tx.wait();

      paused = await token.connect(owner).paused();
      console.log("paused: ", paused.toString());
      expect(paused).to.be.false;
    });

    it("fail if not PAUSER_ROLE call", async () => {
      tx = token.connect(bob).pause();
      await expect(tx).to.be.reverted;

      tx = token.connect(bob).unpause();
      await expect(tx).to.be.reverted;
    });
  });

  // TODO: write test for  ERC20PermitUpgradeable and ERC20VotesUpgradeable
});
