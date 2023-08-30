/* eslint-disable no-unused-vars */
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  Vault,
  MockToken,
  IndexToken,
  // eslint-disable-next-line camelcase
  IndexToken__factory,
  // eslint-disable-next-line node/no-missing-import
} from "../typechain";
import {
  arrayify,
  formatBytes32String,
  keccak256,
  parseEther,
  solidityKeccak256,
} from "ethers/lib/utils";
// eslint-disable-next-line node/no-missing-import
import { tokenName, tokenSymbol } from "./IndexToken";
import { BigNumber, Signer } from "ethers";

export async function deployIndexToken(
  provider = ethers.provider
): Promise<IndexToken> {
  const itf = await (await ethers.getContractFactory("IndexToken")).deploy();
  return IndexToken__factory.connect(itf.address, provider.getSigner());
}

export const toEthSignedMessageHash = (messageHex: any) => {
  const messageBuffer = Buffer.from(messageHex.substring(2), "hex");
  const prefix = Buffer.from(
    `\u0019Ethereum Signed Message:\n${messageBuffer.length}`
  );
  return keccak256(Buffer.concat([prefix, messageBuffer]));
};

export const createWithdrawSignature = async (
  signer: Signer,
  date: string,
  fundId: string,
  asset: string,
  amount: BigNumber,
  to: string
) => {
  const message = [date, fundId, asset, amount, to].join(":");
  const messageHash = solidityKeccak256(["string"], [message]);
  const messageHashBinary = arrayify(messageHash);

  const signature = await signer.signMessage(messageHashBinary);
  const ethSignedMessage = toEthSignedMessageHash(messageHash);

  return { signature, ethSignedMessage };
};

export const AddressZero = "0x0000000000000000000000000000000000000000";
export const AddressOne = "0x0000000000000000000000000000000000000001";
export const DummySignature = AddressZero;

export const TEN_THOUSAND = 10000;
export const ONE_YEAR = 31556952;

describe("Vault tests", function () {
  let vault: Vault;
  let mockToken: MockToken;
  let mockTokenSymbol: string;
  let indexToken: IndexToken;

  let owner: any;
  let bob: any;
  let masterMinter: any;
  let alice: any;
  let feeCollector: any;

  let ownerAddress: string;
  let bobAddress: string;
  let masterMinterAddress: string;
  let feeCollectorAddress: string;

  let tx: any;

  before(async () => {
    // Prep accounts/wallets
    [owner, bob, masterMinter, alice, feeCollector] = await ethers.getSigners();

    mockTokenSymbol = formatBytes32String("TST");
    indexToken = await deployIndexToken();

    ownerAddress = await owner.getAddress();
    bobAddress = await bob.getAddress();
    masterMinterAddress = await masterMinter.getAddress();
    feeCollectorAddress = await feeCollector.getAddress();

    // Init Token
    await indexToken.initialize(tokenName, tokenSymbol, feeCollectorAddress);
    console.log("Index Token initialized");

    // Deploy MockToken
    const MockToken = await ethers.getContractFactory("MockToken");
    mockToken = await MockToken.deploy();
    await mockToken.deployed();
    console.log("Test token deployed at: ", mockToken.address);

    // Mock Token: mint bob 1000 tokens
    await mockToken.mint(bobAddress, parseEther("1000"));

    // Deploy Vault
    const Vault = await ethers.getContractFactory("Vault");
    vault = await Vault.deploy();
    await vault.deployed();
    console.log("Vault deployed at: ", vault.address);
  });

  describe("initialize", function () {
    it("success if values set", async () => {
      // Init Vault
      tx = await vault.initialize(50);
      await tx.wait();
      console.log("Vault initialized");

      expect(await vault.getFee()).to.equal(50);
      // TODO: expect _lastFeeCollection
    });

    it("fail if called more than once", async () => {
      tx = vault.initialize(50);
      await expect(tx).to.be.reverted;
    });
  });

  describe("withdraw", function () {
    it("success if owner call", async () => {
      const withdrawalAmount = parseEther("0.7");

      let vaultBalance = await ethers.provider.getBalance(vault.address);
      expect(vaultBalance).to.equal(0);

      // transfer 1 ETH to Vault
      tx = await owner.sendTransaction({
        to: vault.address,
        value: parseEther("1"),
      });
      await tx.wait();

      vaultBalance = await ethers.provider.getBalance(vault.address);
      expect(vaultBalance).to.equal(parseEther("1"));

      const bobBalanceBefore = await ethers.provider.getBalance(bobAddress);

      // Create withdrawal signature
      const { signature, ethSignedMessage } = await createWithdrawSignature(
        bob,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        withdrawalAmount,
        bobAddress
      );

      // Withdraw
      tx = await vault
        .connect(owner)
        .withdraw(
          bobAddress,
          withdrawalAmount,
          bobAddress,
          ethSignedMessage,
          signature
        );
      await tx.wait();

      // Get fee info
      const fee = await vault.connect(owner).getFee();
      const lastFeeCollection = await vault
        .connect(owner)
        .getLastFeeCollection();

      const blockNumBefore = await ethers.provider.getBlockNumber();
      const blockBefore = await ethers.provider.getBlock(blockNumBefore);
      const timestampBefore = blockBefore.timestamp;
      const timeDelta = timestampBefore - lastFeeCollection.toNumber();

      const proratedFee = fee
        .mul(withdrawalAmount)
        .mul(timeDelta)
        .div(ONE_YEAR)
        .div(TEN_THOUSAND);

      // TODO: incorporate gas cost fee

      expect(await ethers.provider.getBalance(vault.address)).to.equal(
        vaultBalance.sub(withdrawalAmount).add(proratedFee)
      );
      expect(await ethers.provider.getBalance(bobAddress)).to.equal(
        bobBalanceBefore.add(withdrawalAmount).sub(proratedFee)
      );

      /**
       * @dev Cannot expect Bob's NORM token balance to decrease since
       * we did not instantiate an IndexToken contract here.
       * The burn and withdraw methods are separate across these contracts.
       */
    });

    it("fail if not owner call", async () => {
      const withdrawalAmount = parseEther("100");

      const { signature, ethSignedMessage } = await createWithdrawSignature(
        bob,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        withdrawalAmount,
        bobAddress
      );

      // Withdraw
      tx = vault
        .connect(bob)
        .withdraw(
          bobAddress,
          withdrawalAmount,
          bobAddress,
          ethSignedMessage,
          signature
        );

      await expect(tx).to.be.reverted;
    });

    it("fail if invalid signature", async () => {
      const withdrawalAmount = parseEther("100");

      const { signature, ethSignedMessage } = await createWithdrawSignature(
        alice,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        withdrawalAmount,
        bobAddress
      );

      // Withdraw
      tx = vault
        .connect(owner)
        .withdraw(
          bobAddress,
          withdrawalAmount,
          bobAddress,
          ethSignedMessage,
          signature
        );

      await expect(tx).to.be.reverted;
    });

    it("fail if repeat signature", async () => {
      const withdrawalAmount = parseEther("0.7");

      const { signature, ethSignedMessage } = await createWithdrawSignature(
        alice,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        withdrawalAmount,
        bobAddress
      );

      // Withdraw
      tx = vault
        .connect(owner)
        .withdraw(
          bobAddress,
          withdrawalAmount,
          bobAddress,
          ethSignedMessage,
          signature
        );

      await expect(tx).to.be.reverted;
    });
  });

  describe("withdrawToken", function () {
    it("success if owner call and withdrawal owner has Index Tokens", async () => {
      const initialAmount = parseEther("100");
      const withdrawalAmount = parseEther("50");

      const bobBalanceBefore = await mockToken.balanceOf(bobAddress);

      // Deposit 100 TST tokens into the Vault (fake investment)
      tx = await mockToken.connect(owner).mint(vault.address, initialAmount);
      await tx.wait();
      expect(await mockToken.balanceOf(vault.address)).to.equal(initialAmount);

      // Create withdrawal signature
      const { signature, ethSignedMessage } = await createWithdrawSignature(
        bob,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        withdrawalAmount,
        bobAddress
      );

      // Withdraw
      tx = await vault
        .connect(owner)
        .withdrawToken(
          bobAddress,
          mockToken.address,
          withdrawalAmount,
          bobAddress,
          ethSignedMessage,
          signature
        );
      await tx.wait();

      // Get fee info
      const fee = await vault.connect(owner).getFee();
      const lastFeeCollection = await vault
        .connect(owner)
        .getLastFeeCollection();

      const blockNumBefore = await ethers.provider.getBlockNumber();
      const blockBefore = await ethers.provider.getBlock(blockNumBefore);
      const timestampBefore = blockBefore.timestamp;
      const timeDelta = timestampBefore - lastFeeCollection.toNumber();

      const proratedFee = fee
        .mul(withdrawalAmount)
        .mul(timeDelta)
        .div(ONE_YEAR)
        .div(TEN_THOUSAND);

      // TODO: incorporate gas cost fee

      // expect Vault TST tokens to be withdrawn
      expect(await mockToken.balanceOf(vault.address)).to.equal(
        initialAmount.sub(withdrawalAmount).add(proratedFee)
      );

      expect(await mockToken.balanceOf(bobAddress)).to.equal(
        bobBalanceBefore.add(withdrawalAmount).sub(proratedFee)
      );

      /**
       * @dev Cannot expect Bob's NORM token balance to decrease since
       * we did not instantiate an IndexToken contract here.
       * The burn and withdraw methods are separate across these contracts.
       */
    });

    it("fail if not owner call", async () => {
      const withdrawalAmount = parseEther("100");

      // Create withdrawal signature
      const { signature, ethSignedMessage } = await createWithdrawSignature(
        bob,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        withdrawalAmount,
        bobAddress
      );

      // Withdraw
      tx = vault
        .connect(bob)
        .withdrawToken(
          bobAddress,
          mockToken.address,
          withdrawalAmount,
          bobAddress,
          ethSignedMessage,
          signature
        );

      await expect(tx).to.be.reverted;
    });

    it("fail if invalid signature", async () => {
      const withdrawalAmount = parseEther("100");

      // Create withdrawal signature
      const { signature, ethSignedMessage } = await createWithdrawSignature(
        alice,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        withdrawalAmount,
        bobAddress
      );

      // Withdraw
      tx = vault
        .connect(owner)
        .withdrawToken(
          bobAddress,
          mockToken.address,
          withdrawalAmount,
          bobAddress,
          ethSignedMessage,
          signature
        );
      await expect(tx).to.be.reverted;
    });

    it("fail if repeat signature", async () => {
      const withdrawalAmount = parseEther("50");

      // Create withdrawal signature
      const { signature, ethSignedMessage } = await createWithdrawSignature(
        bob,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        withdrawalAmount,
        bobAddress
      );

      // Withdraw
      tx = vault
        .connect(owner)
        .withdrawToken(
          bobAddress,
          mockToken.address,
          withdrawalAmount,
          bobAddress,
          ethSignedMessage,
          signature
        );

      await expect(tx).to.be.reverted;
    });

    // TODO: fail if invalid destination
    // TODO: fail if invalid amount
  });

  describe("pause/unpause", function () {
    it("success if owner call", async () => {
      tx = await vault.connect(owner).pause();
      await tx.wait();

      let paused = await vault.connect(owner).paused();
      // eslint-disable-next-line no-unused-expressions
      expect(paused).to.be.true;

      tx = await vault.connect(owner).unpause();
      await tx.wait();

      paused = await vault.connect(owner).paused();
      // eslint-disable-next-line no-unused-expressions
      expect(paused).to.be.false;
    });

    it("fail if not PAUSER_ROLE call", async () => {
      tx = vault.connect(bob).pause();
      await expect(tx).to.be.reverted;
    });
  });

  describe("adjustFee", function () {
    it("success if valid fee and owner call", async () => {
      tx = await vault.connect(owner).adjustFee(30);
      await tx.wait();

      const updatedFee = await vault.connect(owner).getFee();
      expect(updatedFee).to.equal(30);

      // reset
      (await vault.connect(owner).adjustFee(50)).wait();
      const fee = await vault.connect(owner).getFee();
      expect(fee).to.equal(50);
    });

    it("fail if not owner call", async () => {
      tx = vault.connect(bob).adjustFee(80);
      await expect(tx).to.be.reverted;
    });

    it("fail if fee out of bounds", async () => {
      tx = vault.connect(owner).adjustFee(5001);
      await expect(tx).to.be.reverted;

      tx = vault.connect(owner).adjustFee(-1);
      await expect(tx).to.be.reverted;
    });
  });

  // TODO: revisit and update
  describe("collectFees", function () {
    it("success if owner call", async () => {
      const vaultBalance = await ethers.provider.getBalance(vault.address);
      const lastFeeWithdrawalDateBefore = await vault.getLastFeeCollection();

      // execute collectFees
      tx = await vault.connect(owner).collectFees(feeCollectorAddress);
      await tx.wait();

      // expect feeController balance update
      const fee = await vault.connect(owner).getFee();
      const lastFeeWithdrawalDate = await vault.getLastFeeCollection();

      const timeDelta = lastFeeWithdrawalDate.sub(lastFeeWithdrawalDateBefore);

      const proratedFee = fee
        .mul(vaultBalance)
        .mul(timeDelta)
        .div(ONE_YEAR)
        .div(TEN_THOUSAND);

      // TODO: refactor to expect equal to <tokenFee + tokenFeesToCollect[_symbols[i]]>
      expect(
        await ethers.provider.getBalance(feeCollectorAddress)
      ).to.be.at.least(proratedFee);

      // expect lastFeeWithdrawalDate update
      const blockNumBefore = await ethers.provider.getBlockNumber();
      const blockBefore = await ethers.provider.getBlock(blockNumBefore);
      const timestampBefore = blockBefore.timestamp;
      expect(lastFeeWithdrawalDate).to.equal(timestampBefore);
    });

    it("fail if not owner call", async () => {
      tx = vault.connect(bob).collectFees(feeCollectorAddress);
      await expect(tx).to.be.reverted;
    });
  });

  // TODO: revisit and update
  describe("collectTokenFees", function () {
    it("success if owner call", async () => {
      // bob has deposited 500 TST into the Vault so far...

      const vaultBalanceBefore = await mockToken.balanceOf(vault.address);
      const lastFeeWithdrawalDateBefore = await vault.getLastFeeCollection();

      // execute collectFees
      tx = await vault
        .connect(owner)
        .collectTokenFees(feeCollectorAddress, [mockToken.address]);
      await tx.wait();

      // expect feeController balance update
      const fee = await vault.connect(owner).getFee();
      const lastFeeWithdrawalDate = await vault.getLastFeeCollection();

      const timeDelta = lastFeeWithdrawalDate.sub(lastFeeWithdrawalDateBefore);

      const proratedFee = fee
        .mul(vaultBalanceBefore)
        .mul(timeDelta)
        .div(ONE_YEAR)
        .div(TEN_THOUSAND);

      // TODO: refactor to expect equal to <tokenFee + tokenFeesToCollect[_symbols[i]]>
      expect(await mockToken.balanceOf(feeCollectorAddress)).to.be.at.least(
        proratedFee
      );

      // expect lastFeeWithdrawalDate update
      const blockNumBefore = await ethers.provider.getBlockNumber();
      const blockBefore = await ethers.provider.getBlock(blockNumBefore);
      const timestampBefore = blockBefore.timestamp;
      expect(lastFeeWithdrawalDate).to.equal(timestampBefore);
    });

    it("fail if not owner call", async () => {
      tx = vault
        .connect(bob)
        .collectTokenFees(feeCollectorAddress, [mockToken.address]);
      await expect(tx).to.be.reverted;
    });
  });
});
