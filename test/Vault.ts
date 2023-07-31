import { expect } from "chai";
import { ethers } from "hardhat";
import {
  Vault,
  MockToken,
  IndexToken,
  IndexToken__factory,
} from "../typechain";
import { formatBytes32String, parseEther } from "ethers/lib/utils";

export async function deployIndexToken(
  provider = ethers.provider
): Promise<IndexToken> {
  const ntf = await (await ethers.getContractFactory("IndexToken")).deploy();
  return IndexToken__factory.connect(ntf.address, provider.getSigner());
}

export const AddressZero = "0x0000000000000000000000000000000000000000";
export const AddressOne = "0x0000000000000000000000000000000000000001";

describe("Vault tests", function () {
  let vault: Vault;
  let mockToken: MockToken;
  let mockTokenSymbol: string;
  let indexToken: IndexToken;

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
    // Prep accounts/wallets
    [owner, pauser, feeController, bob] = await ethers.getSigners();

    mockTokenSymbol = formatBytes32String("TST");
    indexToken = await deployIndexToken();

    ownerAddress = await owner.getAddress();
    feeControllerAddress = feeController.getAddress();
    pauserAddress = await pauser.getAddress();
    bobAddress = await bob.getAddress();

    // Deploy MockToken
    const MockToken = await ethers.getContractFactory("MockToken");
    mockToken = await MockToken.deploy();
    await mockToken.deployed();
    console.log("Test token deployed at: ", mockToken.address);

    // Deploy Vault
    const Vault = await ethers.getContractFactory("Vault");
    vault = await Vault.deploy();
    await vault.deployed();
    console.log("Vault deployed at: ", vault.address);

    await vault.initialize(
      pauserAddress,
      feeControllerAddress,
      indexToken.address,
      "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419",
      parseEther("0.005"),
      [formatBytes32String("TST")],
      [mockToken.address],
      ["0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419"]
    );
    console.log("Vault initialized");

    // Mock Token: mint bob 1000 tokens
    await mockToken.mint(bobAddress, parseEther("1000"));
  });

  describe("initialize: replaces constructor for upgradeable contracts", function () {
    it("fail if Vault already initialized", async () => {
      tx = vault
        .connect(owner)
        .initialize(
          pauserAddress,
          feeControllerAddress,
          indexToken.address,
          "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419",
          parseEther("0.005"),
          [formatBytes32String("TST")],
          [mockToken.address],
          ["0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419"]
        );
      await expect(tx).to.be.reverted;
    });
  });

  describe("deposit: add tokens to the Vault", function () {
    it("success if token balance exists", async () => {
      // approve token
      await mockToken.connect(bob).approve(vault.address, parseEther("1000"));

      // deposit
      tx = await vault.connect(bob).deposit(mockTokenSymbol, parseEther("500"));
      await tx.wait();

      // expect updated balances
      expect(await mockToken.balanceOf(vault.address)).to.equal(
        parseEther("500")
      );
      expect(await mockToken.balanceOf(bobAddress)).to.equal(parseEther("500"));
      // expect(await indexToken.balanceOf(bobAddress)).to.equal(500); // TODO: not yet integrated
    });

    it("fail if Vault is paused", async () => {
      tx = await vault.connect(pauser).pause();
      await tx.wait();

      tx = vault.connect(bob).deposit(mockTokenSymbol, parseEther("500"));
      await expect(tx).to.be.reverted;

      // reset
      (await vault.connect(pauser).unpause()).wait();
      const isPaused = await vault.connect(bob).paused();
      expect(isPaused).to.be.false;
    });

    it("fail if insuffienct funds", async () => {
      tx = vault.connect(bob).deposit(mockTokenSymbol, parseEther("2000"));
      await expect(tx).to.be.reverted;
    });

    it("fail if unsupported token", async () => {
      tx = vault
        .connect(bob)
        .deposit(formatBytes32String("ABC"), parseEther("500"));
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid amount", async () => {
      tx = vault.connect(bob).deposit(mockTokenSymbol, parseEther("0"));
      await expect(tx).to.be.reverted;
    });
  });

  describe("withdraw: remove tokens from the Vault", function () {
    // TODO: 🚨 FAILING
    it("success if caller owns NORM tokens", async () => {
      // add normal token to bob
      await indexToken.mint(bobAddress, 500);
      expect(await indexToken.balanceOf(bobAddress)).to.equal(500);

      // withdraw
      tx = await vault.connect(bob).withdraw(500, mockTokenSymbol, bobAddress);
      await tx.wait();

      // expect updated balances
      expect(await mockToken.balanceOf(vault.address)).to.equal(0);
      expect(await mockToken.balanceOf(bobAddress)).to.equal(1000);
      expect(await indexToken.balanceOf(bobAddress)).to.equal(0);
    });

    it("fail if Vault is paused", async () => {
      tx = await vault.connect(pauser).pause();
      await tx.wait();

      tx = vault.connect(bob).withdraw(500, mockTokenSymbol, bobAddress);
      await expect(tx).to.be.reverted;

      // reset
      (await vault.connect(pauser).unpause()).wait();
      const isPaused = await vault.connect(bob).paused();
      expect(isPaused).to.be.false;
    });

    it("fail if invalid amount", async () => {
      tx = vault.connect(bob).withdraw(0, mockTokenSymbol, bobAddress);
      await expect(tx).to.be.reverted;
    });

    it("fail if unsupported token", async () => {
      tx = vault
        .connect(bob)
        .withdraw(500, formatBytes32String("ABC"), bobAddress);
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid destination", async () => {
      tx = vault.connect(bob).withdraw(500, mockTokenSymbol, AddressZero);
      await expect(tx).to.be.reverted;
    });

    it("fail if caller has insufficient Normal Token balance", async () => {
      // zero
      tx = vault.connect(bob).withdraw(500, mockTokenSymbol, bobAddress);
      await expect(tx).to.be.reverted;

      // to much
      tx = vault.connect(bob).withdraw(1100, mockTokenSymbol, bobAddress);
      await expect(tx).to.be.reverted;
    });

    // TODO: not yet integrated
    // it("fail if Vault has insufficient funds", async () => {
    //   tx = vault.connect(bob).withdraw(100, mockTokenSymbol, bob);
    //   await expect(tx).to.be.reverted;
    // });
  });

  // /*///////////////////////////////////////////////////////////////
  //                       Admin functions
  //   //////////////////////////////////////////////////////////////*/

  describe("whitelistToken: add Vault token support", function () {
    const newTokenSymbol = formatBytes32String("ABC");

    it("success if DEFAULT_ADMIN_ROLE call", async () => {
      tx = await vault
        .connect(owner)
        .whitelistToken(
          newTokenSymbol,
          AddressOne,
          "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419"
        );
      await tx.wait();

      const whitelistedTokenAddress = await vault
        .connect(bob)
        .getWhitelistedTokenAddress(newTokenSymbol);
      expect(whitelistedTokenAddress).to.equal(AddressOne);
    });

    it("fail if not DEFAULT_ADMIN_ROLE call", async () => {
      tx = vault
        .connect(bob)
        .whitelistToken(
          newTokenSymbol,
          AddressOne,
          "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419"
        );
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid token address", async () => {
      tx = vault
        .connect(bob)
        .whitelistToken(
          newTokenSymbol,
          AddressZero,
          "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419"
        );
      await expect(tx).to.be.reverted;
    });
  });

  describe("pause/unpause: temporarily enable/disable functions marked with whenNotPaused", function () {
    it("success if PAUSER_ROLE call", async () => {
      tx = await vault.connect(pauser).pause();
      await tx.wait();

      let paused = await vault.connect(pauser).paused();
      expect(paused).to.be.true;

      tx = await vault.connect(pauser).unpause();
      await tx.wait();

      paused = await vault.connect(pauser).paused();
      expect(paused).to.be.false;
    });

    it("fail if not PAUSER_ROLE call", async () => {
      tx = vault.connect(bob).pause();
      await expect(tx).to.be.reverted;
    });
  });

  describe("adjustFee: update the annual fee", function () {
    it("success if valid fee and FEE_CONTROLLER_ROLE / feeController call", async () => {
      tx = await vault.connect(feeController).adjustFee(parseEther("0.003"));
      await tx.wait();

      const updatedFee = await vault.connect(feeController).getFee();
      expect(updatedFee).to.equal(parseEther("0.003"));

      // reset
      (
        await vault.connect(feeController).adjustFee(parseEther("0.005"))
      ).wait();
      const fee = await vault.connect(bob).getFee();
      expect(fee).to.equal(parseEther("0.005"));
    });

    it("fail if not FEE_CONTROLLER_ROLE / feeController call", async () => {
      tx = vault.connect(bob).adjustFee(parseEther("0.008"));
      await expect(tx).to.be.reverted;
    });

    it("fail if fee out of bounds", async () => {
      tx = vault.connect(feeController).adjustFee(parseEther("0.06"));
      await expect(tx).to.be.reverted;

      tx = vault.connect(feeController).adjustFee(parseEther("-0.005"));
      await expect(tx).to.be.reverted;
    });
  });

  describe("withdrawFee: claim monthly fee proceeds", function () {
    it("success if ", async () => {
      // bob has deposited 500 TST into the Vault so far...

      const vaultBalanceBefore = await mockToken.balanceOf(vault.address);
      const lastFeeWithdrawalDateBefore = await vault
        .connect(bob)
        .getLastFeeWithdrawalDate();

      // execute withdrawFee
      tx = await vault.connect(feeController).withdrawFee([mockTokenSymbol]);
      await tx.wait();

      // expect feeController balance update
      const fee = await vault.connect(bob).getFee();
      const lastFeeWithdrawalDate = await vault
        .connect(bob)
        .getLastFeeWithdrawalDate();

      const dayDiff = lastFeeWithdrawalDate
        .sub(lastFeeWithdrawalDateBefore)
        .div(60)
        .div(60)
        .div(24);
      expect(dayDiff).to.equal(30);

      const expectedFee = fee.div(365).mul(dayDiff).mul(vaultBalanceBefore);
      expect(await mockToken.balanceOf(feeControllerAddress)).to.equal(
        expectedFee
      );

      // expect lastFeeWithdrawalDate update
      const blockNumBefore = await ethers.provider.getBlockNumber();
      const blockBefore = await ethers.provider.getBlock(blockNumBefore);
      const timestampBefore = blockBefore.timestamp;
      expect(lastFeeWithdrawalDate).to.equal(timestampBefore);
    });

    it("fail if not FEE_CONTROLLER_ROLE / feeController call", async () => {
      tx = vault.connect(bob).withdrawFee([mockTokenSymbol]);
      await expect(tx).to.be.reverted;
    });
  });
});
