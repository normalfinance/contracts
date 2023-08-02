import { expect } from "chai";
import { ethers } from "hardhat";
import { Proxy, Vault, IndexToken, IndexToken__factory } from "../typechain";
import { parseEther } from "ethers/lib/utils";

export async function deployIndexToken(
  provider = ethers.provider
): Promise<IndexToken> {
  const ntf = await (await ethers.getContractFactory("IndexToken")).deploy();
  return IndexToken__factory.connect(ntf.address, provider.getSigner());
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

    ownerAddress = await owner.getAddress();
    feeControllerAddress = feeController.getAddress();
    pauserAddress = await pauser.getAddress();
    bobAddress = await bob.getAddress();

    // Init Token
    await token.initialize("NormalToken", "NORM");
    console.log("Token initialized");

    // Deploy Proxy
    const Proxy = await ethers.getContractFactory("Proxy");
    proxy = await Proxy.deploy();
    await proxy.deployed();
    console.log("Proxy deployed at: ", proxy.address);

    await vault.initialize(
      pauserAddress,
      feeControllerAddress,
      token.address,
      50,
      [],
      []
    );
    console.log("Vault initialized");
  });

  describe("updateBalance: ", function () {
    it("success if OWNER call", async () => {
      tx = await proxy.connect(owner).updateBalance(bobAddress, parseEther("100"));
      await tx.wait();

      // expect();
    });

    it("fail if not DEFAULT_ADMIN_ROLE call", async () => {
      tx = token.connect(bob).mint(bobAddress, 100);
      await expect(tx).to.be.reverted;
    });
  });

  describe("batchWithdraw: ", function () {
    it("success if OWNER call", async () => {
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
  });
});
