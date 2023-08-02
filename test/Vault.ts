import { expect } from "chai";
import { ethers, web3 } from "hardhat";
// import Web3 from 'web3';
import {
  Vault,
  MockToken,
  IndexToken,
  IndexToken__factory,
} from "../typechain";
import {
  formatBytes32String,
  formatEther,
  keccak256,
  parseEther,
} from "ethers/lib/utils";

export async function deployIndexToken(
  provider = ethers.provider
): Promise<IndexToken> {
  const ntf = await (await ethers.getContractFactory("IndexToken")).deploy();
  return IndexToken__factory.connect(ntf.address, provider.getSigner());
}

function toEthSignedMessageHash(messageHex: any) {
  const messageBuffer = Buffer.from(messageHex.substring(2), "hex");
  const prefix = Buffer.from(
    `\u0019Ethereum Signed Message:\n${messageBuffer.length}`
  );
  return keccak256(Buffer.concat([prefix, messageBuffer]));
}

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
  let feeController: any;
  let pauser: any;
  let bob: any;
  let alice: any;

  let ownerAddress: string;
  let feeControllerAddress: string;
  let pauserAddress: string;
  let bobAddress: string;
  let aliceAddress: string;

  let ethSignedMessage: string;
  let signature: string;
  let tx: any;

  async function createWithdrawSignature(
    symbol: string,
    amount: string,
    destination: string,
    signer: string
  ) {
    const messageHash = web3.utils.sha3(`${symbol}:${amount}:${destination}`)!;
    signature = await web3.eth.sign(messageHash, signer);
    ethSignedMessage = toEthSignedMessageHash(messageHash);
  }

  before(async () => {
    // Prep accounts/wallets
    [owner, pauser, feeController, bob, alice] = await ethers.getSigners();

    mockTokenSymbol = formatBytes32String("TST");
    indexToken = await deployIndexToken();

    ownerAddress = await owner.getAddress();
    feeControllerAddress = feeController.getAddress();
    pauserAddress = await pauser.getAddress();
    bobAddress = await bob.getAddress();
    aliceAddress = await alice.getAddress();

    // Init Token
    await indexToken.initialize("NormalToken", "NORM");
    console.log("Token initialized");

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
      50,
      [formatBytes32String("TST")],
      [mockToken.address]
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
          parseEther("0.005"),
          [formatBytes32String("TST")],
          [mockToken.address]
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
    it("success if caller owns Index tokens", async () => {
      const withdrawalAmount = parseEther("100");
      const vaultBalanceBefore = await mockToken.balanceOf(vault.address);
      const aliceBalanceBefore = await mockToken.balanceOf(alice.address);

      // add normal token to bob
      tx = await indexToken.connect(owner).mint(bobAddress, withdrawalAmount);
      await tx.wait();
      expect(await indexToken.balanceOf(bobAddress)).to.equal(withdrawalAmount);

      // withdraw
      await createWithdrawSignature(
        "TST",
        aliceAddress,
        withdrawalAmount.toString(),
        bobAddress
      );

      tx = await vault
        .connect(owner)
        .withdraw(
          bobAddress,
          mockTokenSymbol,
          withdrawalAmount,
          aliceAddress,
          withdrawalAmount,
          ethSignedMessage,
          signature
        );
      await tx.wait();

      const fee = await vault.connect(bob).getFee();
      const lastFeeWithdrawalDate = await vault
        .connect(bob)
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

      // expect updated balances
      expect(await mockToken.balanceOf(vault.address)).to.equal(
        vaultBalanceBefore.sub(withdrawalAmount).add(proratedFee)
      );
      expect(await mockToken.balanceOf(aliceAddress)).to.equal(
        aliceBalanceBefore.add(withdrawalAmount).sub(proratedFee)
      );
      // expect(await indexToken.balanceOf(bobAddress)).to.equal(0);
    });

    it("fail if not DEFAULT_ADMIN_ROLE call", async () => {
      await createWithdrawSignature(
        "TST",
        bobAddress,
        parseEther("500").toString(),
        bobAddress
      );
      tx = vault
        .connect(bob)
        .withdraw(
          bobAddress,
          mockTokenSymbol,
          parseEther("500"),
          bobAddress,
          500,
          ethSignedMessage,
          signature
        );
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid amount", async () => {
      await createWithdrawSignature(
        "TST",
        bobAddress,
        parseEther("0").toString(),
        bobAddress
      );
      tx = vault
        .connect(owner)
        .withdraw(
          bobAddress,
          formatBytes32String("ABC"),
          parseEther("0"),
          bobAddress,
          500,
          ethSignedMessage,
          signature
        );
      await expect(tx).to.be.reverted;

      await createWithdrawSignature(
        "ABC",
        bobAddress,
        parseEther("10000").toString(),
        bobAddress
      );
      tx = vault
        .connect(owner)
        .withdraw(
          bobAddress,
          formatBytes32String("ABC"),
          parseEther("10000"),
          bobAddress,
          500,
          ethSignedMessage,
          signature
        );
      await expect(tx).to.be.reverted;
    });

    it("fail if unsupported token", async () => {
      await createWithdrawSignature(
        "ABC",
        bobAddress,
        parseEther("500").toString(),
        bobAddress
      );
      tx = vault
        .connect(owner)
        .withdraw(
          bobAddress,
          formatBytes32String("ABC"),
          parseEther("500"),
          bobAddress,
          500,
          ethSignedMessage,
          signature
        );
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid destination", async () => {
      await createWithdrawSignature(
        "TST",
        bobAddress,
        parseEther("500").toString(),
        bobAddress
      );
      tx = vault
        .connect(owner)
        .withdraw(
          bobAddress,
          mockTokenSymbol,
          parseEther("500"),
          AddressZero,
          500,
          ethSignedMessage,
          signature
        );
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid Index Token balance", async () => {
      // zero
      await createWithdrawSignature(
        "TST",
        bobAddress,
        parseEther("500").toString(),
        bobAddress
      );
      tx = vault
        .connect(owner)
        .withdraw(
          bobAddress,
          mockTokenSymbol,
          parseEther("500"),
          bobAddress,
          0,
          ethSignedMessage,
          signature
        );
      await expect(tx).to.be.reverted;

      // to0 much
      await createWithdrawSignature(
        "TST",
        bobAddress,
        parseEther("500").toString(),
        bobAddress
      );
      tx = vault
        .connect(owner)
        .withdraw(
          bobAddress,
          mockTokenSymbol,
          parseEther("500"),
          bobAddress,
          10000,
          ethSignedMessage,
          signature
        );
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid signature", async () => {
      await createWithdrawSignature(
        "TST",
        aliceAddress,
        parseEther("500").toString(),
        bobAddress
      );
      tx = vault
        .connect(owner)
        .withdraw(
          bobAddress,
          mockTokenSymbol,
          parseEther("500"),
          bobAddress,
          500,
          ethSignedMessage,
          signature
        );
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
        .whitelistToken(newTokenSymbol, AddressOne);
      await tx.wait();

      const whitelistedToken = await vault
        .connect(bob)
        .getWhitelistedToken(newTokenSymbol);
      expect(whitelistedToken).to.equal(AddressOne);
    });

    it("fail if not DEFAULT_ADMIN_ROLE call", async () => {
      tx = vault.connect(bob).whitelistToken(newTokenSymbol, AddressOne);
      await expect(tx).to.be.reverted;
    });

    it("fail if invalid token address", async () => {
      tx = vault.connect(bob).whitelistToken(newTokenSymbol, AddressZero);
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
      tx = await vault.connect(feeController).adjustFee(30);
      await tx.wait();

      const updatedFee = await vault.connect(feeController).getFee();
      expect(updatedFee).to.equal(30);

      // reset
      (await vault.connect(feeController).adjustFee(50)).wait();
      const fee = await vault.connect(bob).getFee();
      expect(fee).to.equal(50);
    });

    it("fail if not FEE_CONTROLLER_ROLE / feeController call", async () => {
      tx = vault.connect(bob).adjustFee(80);
      await expect(tx).to.be.reverted;
    });

    it("fail if fee out of bounds", async () => {
      tx = vault.connect(feeController).adjustFee(5001);
      await expect(tx).to.be.reverted;

      tx = vault.connect(feeController).adjustFee(-1);
      await expect(tx).to.be.reverted;
    });
  });

  describe("withdrawFee: claim monthly fee proceeds", function () {
    it("success if FEE_CONTROLLER_ROLE call", async () => {
      // bob has deposited 500 TST into the Vault so far...

      const vaultBalanceBefore = await mockToken.balanceOf(vault.address);
      const lastFeeWithdrawalDateBefore = await vault
        .connect(bob)
        .getLastFeeWithdrawalDate(mockTokenSymbol);

      // execute withdrawFee
      tx = await vault.connect(feeController).withdrawFee([mockTokenSymbol]);
      await tx.wait();

      // expect feeController balance update
      const fee = await vault.connect(bob).getFee();
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
      expect(await mockToken.balanceOf(feeControllerAddress)).to.be.at.least(
        proratedFee
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
