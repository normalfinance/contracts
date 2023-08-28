import { expect } from "chai";
import { ethers } from "hardhat";
import {
  IndexToken,
  // eslint-disable-next-line camelcase
  IndexToken__factory,
  MockToken,
  // eslint-disable-next-line node/no-missing-import
} from "../typechain";
import { formatBytes32String, parseEther } from "ethers/lib/utils";
// eslint-disable-next-line node/no-missing-import
import { createWithdrawSignature } from "./Vault";

export async function deployIndexToken(
  provider = ethers.provider
): Promise<IndexToken> {
  const itf = await (await ethers.getContractFactory("IndexToken")).deploy();
  return IndexToken__factory.connect(itf.address, provider.getSigner());
}

export const AddressZero = "0x0000000000000000000000000000000000000000";
export const AddressOne = "0x0000000000000000000000000000000000000001";
export const tokenName = "NormalToken";
export const tokenSymbol = "NORM";
const newMinterAllowance = parseEther("1000");

describe("Index Token tests", function () {
  // let vault: Vault;
  let token: IndexToken;
  let mockToken: MockToken;
  let mockTokenSymbol: string;

  let owner: any;
  let bob: any;
  let masterMinter: any;
  let newMinter: any;
  let newMasterMinter: any;

  // let ownerAddress: string;
  let bobAddress: string;
  let masterMinterAddress: string;
  let newMinterAddress: string;
  let newMasterMinterAddress: string;

  let tx: any;

  before(async () => {
    [owner, bob, masterMinter, newMinter, newMasterMinter] =
      await ethers.getSigners();

    mockTokenSymbol = formatBytes32String("TST");
    token = await deployIndexToken();

    // ownerAddress = await owner.getAddress();
    bobAddress = await bob.getAddress();
    masterMinterAddress = await masterMinter.getAddress();
    newMinterAddress = await newMinter.getAddress();
    newMasterMinterAddress = await newMasterMinter.getAddress();

    // Deploy MockToken
    const MockToken = await ethers.getContractFactory("MockToken");
    mockToken = await MockToken.deploy();
    await mockToken.deployed();
    console.log("Test token deployed at: ", mockToken.address);
  });

  describe("initialize", function () {
    it("success if values set", async () => {
      // Init Token
      tx = await token.initialize(tokenName, tokenSymbol, masterMinterAddress);
      await tx.wait();
      console.log("Token initialized");

      expect(await token.name()).to.equal(tokenName);
      expect(await token.symbol()).to.equal(tokenSymbol);
      expect(await token.masterMinter()).to.equal(masterMinterAddress);
    });

    it("fail if called more than once", async () => {
      tx = token.initialize(tokenName, tokenSymbol, masterMinterAddress);
      await expect(tx).to.be.reverted;
    });

    // TODO: fail if masterMinter is zero address
  });

  describe("configureMinter", function () {
    it("success if master minter call", async () => {
      tx = await token
        .connect(masterMinter)
        .configureMinter(newMinterAddress, newMinterAllowance);
      await tx.wait();

      expect(await token.isMinter(newMinterAddress)).to.equal(true);
      expect(await token.minterAllowance(newMinterAddress)).to.equal(
        newMinterAllowance
      );
    });

    it("fail if not master minter call", async () => {
      tx = token
        .connect(bob)
        .configureMinter(newMinterAddress, newMinterAllowance);
      await expect(tx).to.be.reverted;
    });

    // TODO: fail if paused
  });

  describe("mint", function () {
    it("success if minter call", async () => {
      const bobBalanceBefore = await token.balanceOf(bobAddress);
      expect(bobBalanceBefore).to.equal(parseEther("0"));

      tx = await token.connect(newMinter).mint(bobAddress, parseEther("100"));
      await tx.wait();

      // tokens minted
      expect(await token.balanceOf(bobAddress)).to.equal(
        bobBalanceBefore.add(parseEther("100"))
      );
      // updated ownership
      expect(await token.getOwnership(bobAddress)).to.equal(parseEther("100"));
      // decremented minter allowance
      expect(await token.minterAllowance(newMinterAddress)).to.equal(
        newMinterAllowance.sub(parseEther("100"))
      );
    });

    it("fail if not minter call", async () => {
      tx = token.connect(bob).mint(bobAddress, 100);
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
      // eslint-disable-next-line no-unused-expressions
      expect(isPaused).to.be.false;
    });

    it("fail if invalid param", async () => {
      tx = token.connect(newMinter).mint(AddressZero, 100);
      await expect(tx).to.be.reverted;

      tx = token.connect(newMinter).mint(bobAddress, 0);
      await expect(tx).to.be.reverted;
    });
  });

  describe("burnForWithdraw", function () {
    it("success if minter call", async () => {
      const bobBalanceBefore = await token.balanceOf(bobAddress);
      expect(bobBalanceBefore).to.equal(parseEther("100"));

      const tokensToBurn = parseEther("50");

      const { signature, ethSignedMessage } = await createWithdrawSignature(
        bob,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        tokensToBurn,
        bobAddress
      );

      tx = await token.connect(newMinter).burnForWithdraw(
        tokensToBurn,
        {
          owner: bobAddress,
          symbol: mockTokenSymbol,
          amount: tokensToBurn,
          to: bobAddress,
        },
        ethSignedMessage,
        signature
      );
      await tx.wait();

      // tokens burned
      expect(await token.balanceOf(bobAddress)).to.equal(
        bobBalanceBefore.sub(tokensToBurn)
      );
      // updated ownership
      expect(await token.getOwnership(bobAddress)).to.equal(
        bobBalanceBefore.sub(tokensToBurn)
      );
    });

    it("fail if not minter call", async () => {
      const tokensToBurn = parseEther("50");

      const { signature, ethSignedMessage } = await createWithdrawSignature(
        bob,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        tokensToBurn,
        bobAddress
      );

      tx = token.connect(bob).burnForWithdraw(
        tokensToBurn,
        {
          owner: bobAddress,
          symbol: mockTokenSymbol,
          amount: tokensToBurn,
          to: bobAddress,
        },
        ethSignedMessage,
        signature
      );
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid signature", async () => {
      const tokensToBurn = parseEther("50");

      const { signature, ethSignedMessage } = await createWithdrawSignature(
        masterMinter,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        tokensToBurn,
        bobAddress
      );

      tx = token.connect(bob).burnForWithdraw(
        tokensToBurn,
        {
          owner: bobAddress,
          symbol: mockTokenSymbol,
          amount: tokensToBurn,
          to: bobAddress,
        },
        ethSignedMessage,
        signature
      );
      await expect(tx).to.be.reverted;
    });

    it("fail if repeat signature", async () => {
      const tokensToBurn = parseEther("50");

      const { signature, ethSignedMessage } = await createWithdrawSignature(
        bob,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        tokensToBurn,
        bobAddress
      );

      tx = token.connect(bob).burnForWithdraw(
        tokensToBurn,
        {
          owner: bobAddress,
          symbol: mockTokenSymbol,
          amount: tokensToBurn,
          to: bobAddress,
        },
        ethSignedMessage,
        signature
      );
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid params", async () => {
      // Invalid amount
      const tokensToBurn = parseEther("80");

      const { signature, ethSignedMessage } = await createWithdrawSignature(
        bob,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        tokensToBurn,
        bobAddress
      );

      tx = token.connect(bob).burnForWithdraw(
        tokensToBurn,
        {
          owner: bobAddress,
          symbol: mockTokenSymbol,
          amount: tokensToBurn,
          to: bobAddress,
        },
        ethSignedMessage,
        signature
      );
      await expect(tx).to.be.reverted;

      // Invalid withdrawal owner
      const _tokensToBurn = parseEther("50");

      const { signature: _signature, ethSignedMessage: _ethSignedMessage } =
        await createWithdrawSignature(
          bob,
          new Date().toISOString().substring(0, 10),
          "tmf",
          mockTokenSymbol,
          _tokensToBurn,
          bobAddress
        );

      tx = token.connect(bob).burnForWithdraw(
        _tokensToBurn,
        {
          owner: AddressZero,
          symbol: mockTokenSymbol,
          amount: _tokensToBurn,
          to: bobAddress,
        },
        _ethSignedMessage,
        _signature
      );
      await expect(tx).to.be.reverted;
    });
  });

  describe("pause/unpause", function () {
    it("success if PAUSER_ROLE call", async () => {
      tx = await token.connect(owner).pause();
      await tx.wait();

      let paused = await token.connect(owner).paused();
      // eslint-disable-next-line no-unused-expressions
      expect(paused).to.be.true;

      tx = await token.connect(owner).unpause();
      await tx.wait();

      paused = await token.connect(owner).paused();
      // eslint-disable-next-line no-unused-expressions
      expect(paused).to.be.false;
    });

    it("fail if not PAUSER_ROLE call", async () => {
      tx = token.connect(bob).pause();
      await expect(tx).to.be.reverted;

      tx = token.connect(bob).unpause();
      await expect(tx).to.be.reverted;
    });
  });

  describe("removeMinter", function () {
    it("success if master minter call", async () => {
      tx = await token.connect(masterMinter).removeMinter(newMinterAddress);
      await tx.wait();

      expect(await token.isMinter(newMinterAddress)).to.equal(false);
      expect(await token.minterAllowance(newMinterAddress)).to.equal(0);
    });

    it("fail if not master minter call", async () => {
      tx = token.connect(bob).removeMinter(newMinterAddress);
      await expect(tx).to.be.reverted;
    });
  });

  describe("updateMasterMinter", function () {
    it("success if owner call", async () => {
      tx = await token
        .connect(owner)
        .updateMasterMinter(newMasterMinterAddress);
      await tx.wait();

      expect(await token.masterMinter()).to.equal(newMasterMinterAddress);
    });

    it("fail if not owner call", async () => {
      tx = token.connect(bob).updateMasterMinter(newMasterMinterAddress);
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid address", async () => {
      tx = token.connect(newMasterMinter).updateMasterMinter(AddressZero);
      await expect(tx).to.be.reverted;
    });
  });
});
