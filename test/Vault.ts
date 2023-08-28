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

  let ownerAddress: string;
  let bobAddress: string;
  let masterMinterAddress: string;

  let tx: any;

  before(async () => {
    // Prep accounts/wallets
    [owner, bob, masterMinter, alice] = await ethers.getSigners();

    mockTokenSymbol = formatBytes32String("TST");
    indexToken = await deployIndexToken();

    ownerAddress = await owner.getAddress();
    bobAddress = await bob.getAddress();
    masterMinterAddress = await masterMinter.getAddress();

    // Init Token
    await indexToken.initialize(tokenName, tokenSymbol, masterMinterAddress);
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
      tx = await vault.initialize(
        50,
        [formatBytes32String("TST")],
        [mockToken.address]
      );
      await tx.wait();
      console.log("Vault initialized");

      expect(await vault.getFee()).to.equal(50);
      expect(
        await vault.getWhitelistedToken(formatBytes32String("TST"))
      ).to.equal(mockToken.address);
    });

    it("fail if called more than once", async () => {
      tx = vault.initialize(
        50,
        [formatBytes32String("TST")],
        [mockToken.address]
      );
      await expect(tx).to.be.reverted;
    });
  });

  describe("withdraw", function () {
    it("success if owner call and withdrawal owner has Index Tokens", async () => {
      const initialAmount = parseEther("100");
      const withdrawalAmount = parseEther("50");

      // Deposit 100 TST tokens into the Vault (fake investment)
      tx = await mockToken.connect(owner).mint(vault.address, initialAmount);
      await tx.wait();
      expect(await mockToken.balanceOf(vault.address)).to.equal(initialAmount);

      // Configure NORM minter
      tx = await indexToken
        .connect(masterMinter)
        .configureMinter(masterMinterAddress, parseEther("100"));
      await tx.wait();

      // Mint 100 NORM tokens to Bob (for fake investment)
      tx = await indexToken
        .connect(masterMinter)
        .mint(bobAddress, initialAmount);
      await tx.wait();
      expect(await indexToken.balanceOf(bobAddress)).to.equal(initialAmount);
      expect(await indexToken.getOwnership(bobAddress)).to.equal(initialAmount);

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
      tx = await vault.connect(owner).withdraw(
        {
          owner: bobAddress,
          symbol: mockTokenSymbol,
          amount: withdrawalAmount,
          to: bobAddress,
        },
        ethSignedMessage,
        signature
      );
      await tx.wait();

      // Get fee info
      const fee = await vault.connect(owner).getFee();
      const lastFeeWithdrawalDate = await vault
        .connect(owner)
        .getLastFeeWithdrawalDate(mockTokenSymbol);

      const blockNumBefore = await ethers.provider.getBlockNumber();
      const blockBefore = await ethers.provider.getBlock(blockNumBefore);
      const timestampBefore = blockBefore.timestamp;
      const timeDelta = timestampBefore - lastFeeWithdrawalDate.toNumber();

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

      tx = vault.connect(bob).withdraw(
        {
          owner: bobAddress,
          symbol: mockTokenSymbol,
          amount: withdrawalAmount,
          to: bobAddress,
        },
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

      tx = vault.connect(owner).withdraw(
        {
          owner: bobAddress,
          symbol: mockTokenSymbol,
          amount: withdrawalAmount,
          to: bobAddress,
        },
        ethSignedMessage,
        signature
      );

      await expect(tx).to.be.reverted;
    });

    it("fail if repeat signature", async () => {
      const withdrawalAmount = parseEther("50");

      const { signature, ethSignedMessage } = await createWithdrawSignature(
        bob,
        new Date().toISOString().substring(0, 10),
        "tmf",
        mockTokenSymbol,
        withdrawalAmount,
        bobAddress
      );

      tx = vault.connect(owner).withdraw(
        {
          owner: bobAddress,
          symbol: mockTokenSymbol,
          amount: withdrawalAmount,
          to: bobAddress,
        },
        ethSignedMessage,
        signature
      );

      await expect(tx).to.be.reverted;
    });

    it("fail if unsupported token", async () => {
      const withdrawalAmount = parseEther("100");

      const { signature, ethSignedMessage } = await createWithdrawSignature(
        bob,
        new Date().toISOString().substring(0, 10),
        "tmf",
        formatBytes32String("ABC"),
        withdrawalAmount,
        bobAddress
      );

      tx = vault.connect(owner).withdraw(
        {
          owner: bobAddress,
          symbol: formatBytes32String("ABC"),
          amount: withdrawalAmount,
          to: bobAddress,
        },
        ethSignedMessage,
        signature
      );

      await expect(tx).to.be.reverted;
    });

    // TODO: fail if invalid destination
    // TODO: fail if invalid amount
  });

  describe("whitelistToken", function () {
    const newTokenSymbol = formatBytes32String("ABC");

    it("success if owner call", async () => {
      tx = await vault
        .connect(owner)
        .whitelistToken(newTokenSymbol, AddressOne);
      await tx.wait();

      const whitelistedToken = await vault
        .connect(owner)
        .getWhitelistedToken(newTokenSymbol);
      expect(whitelistedToken).to.equal(AddressOne);
    });

    it("fail if not owner call", async () => {
      tx = vault.connect(bob).whitelistToken(newTokenSymbol, AddressOne);
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid token address", async () => {
      tx = vault.connect(owner).whitelistToken(newTokenSymbol, AddressZero);
      await expect(tx).to.be.reverted;
    });
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

  describe("withdrawFee", function () {
    it("success if owner call", async () => {
      // bob has deposited 500 TST into the Vault so far...

      const vaultBalanceBefore = await mockToken.balanceOf(vault.address);
      const lastFeeWithdrawalDateBefore = await vault
        .connect(bob)
        .getLastFeeWithdrawalDate(mockTokenSymbol);

      // execute withdrawFee
      tx = await vault.connect(owner).withdrawFee([mockTokenSymbol]);
      await tx.wait();

      // expect feeController balance update
      const fee = await vault.connect(owner).getFee();
      const lastFeeWithdrawalDate = await vault
        .connect(bob)
        .getLastFeeWithdrawalDate(mockTokenSymbol);

      const timeDelta = lastFeeWithdrawalDate.sub(lastFeeWithdrawalDateBefore);

      const proratedFee = fee
        .mul(vaultBalanceBefore)
        .mul(timeDelta)
        .div(ONE_YEAR)
        .div(TEN_THOUSAND);
      // TODO: refactor to expect equal to <tokenFee + tokenFeesToCollect[_symbols[i]]>
      expect(await mockToken.balanceOf(ownerAddress)).to.be.at.least(
        proratedFee
      );

      // expect lastFeeWithdrawalDate update
      const blockNumBefore = await ethers.provider.getBlockNumber();
      const blockBefore = await ethers.provider.getBlock(blockNumBefore);
      const timestampBefore = blockBefore.timestamp;
      expect(lastFeeWithdrawalDate).to.equal(timestampBefore);
    });

    it("fail if not owner call", async () => {
      tx = vault.connect(bob).withdrawFee([mockTokenSymbol]);
      await expect(tx).to.be.reverted;
    });
  });
});
