import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

describe("X1000", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployX1000Fixture() {
    const [owner, otherAccount] = await ethers.getSigners();
    //deploy Bookie
    const Bookie = await ethers.getContractFactory("Bookie", owner);
    const bookie = await upgrades.deployProxy(Bookie, [], {
      initializer: "initialize",
    });
    //deploy mockUSDC
    const MockUSDC = await ethers.getContractFactory("MockUSDC", owner);
    const mockUSDC = await MockUSDC.deploy(10000000 * 10 ** 6);
    //transfer 1m to owner
    await (
      await mockUSDC.transfer(await owner.getAddress(), 1000000 * 10 ** 6)
    ).wait();
    //deploy Credit
    const Credit = await ethers.getContractFactory("Credit", owner);
    const credit = await upgrades.deployProxy(
      Credit,
      [
        await bookie.getAddress(),
        await mockUSDC.getAddress(),
        10000000,
        2000000000,
      ],
      {
        initializer: "initialize",
      }
    );
    //deploy x1000
    const X1000 = await ethers.getContractFactory("X1000", owner);
    const x1000 = await upgrades.deployProxy(
      X1000,
      [await bookie.getAddress(), await credit.getAddress()],
      {
        initializer: "initialize",
      }
    );
    await x1000.waitForDeployment();
    return { x1000, bookie, mockUSDC, credit, owner, otherAccount };
  }

  describe("Deployment", function () {
    it("Should deploy success", async function () {
      const { x1000, bookie, credit, owner, otherAccount } = await loadFixture(
        deployX1000Fixture
      );
    });
    it("Should topup system success", async function () {
      const { x1000, bookie, mockUSDC, credit, owner, otherAccount } =
        await loadFixture(deployX1000Fixture);
      await (
        await mockUSDC
          .connect(owner)
          .approve(await credit.getAddress(), 1000000000000)
      ).wait();
      expect(
        await mockUSDC.allowance(
          await owner.getAddress(),
          await credit.getAddress()
        )
      ).to.eq(1000000000000);
      await (await credit.topupSystem(1000000000000)).wait();
      expect(await credit.platformCredit()).to.equal(1000000000000);
    });
    it("Should topup user success", async function () {
      const { x1000, bookie, mockUSDC, credit, owner, otherAccount } =
        await loadFixture(deployX1000Fixture);
      await (
        await mockUSDC
          .connect(owner)
          .approve(await credit.getAddress(), 1000000000000)
      ).wait();
      expect(
        await mockUSDC.allowance(
          await owner.getAddress(),
          await credit.getAddress()
        )
      ).to.eq(1000000000000);
      await (await credit.topupSystem(1000000000000)).wait();
      expect(await credit.platformCredit()).to.equal(1000000000000);
      //fund mockUSDC to user
      await (
        await mockUSDC.connect(owner).transfer(otherAccount.address, 1000000000)
      ).wait();
      //approve mockUSDC to credit
      await (
        await mockUSDC
          .connect(otherAccount)
          .approve(await credit.getAddress(), 1000000000)
      ).wait();
      //topup user
      await (await credit.connect(otherAccount).topup(1000000000)).wait();
      expect(await credit.getCredit(otherAccount.address)).to.equal(1000000000);
    });
    it("Should open position success", async function () {
      const { x1000, bookie, mockUSDC, credit, owner, otherAccount } =
        await loadFixture(deployX1000Fixture);
      await (
        await mockUSDC
          .connect(owner)
          .approve(await credit.getAddress(), 1000000000000)
      ).wait();
      expect(
        await mockUSDC.allowance(
          await owner.getAddress(),
          await credit.getAddress()
        )
      ).to.eq(1000000000000);
      await (await credit.topupSystem(1000000000000)).wait();
      expect(await credit.platformCredit()).to.equal(1000000000000);
      //fund mockUSDC to user
      await (
        await mockUSDC.connect(owner).transfer(otherAccount.address, 1000000000)
      ).wait();
      //approve mockUSDC to credit
      await (
        await mockUSDC
          .connect(otherAccount)
          .approve(await credit.getAddress(), 1000000000)
      ).wait();
      //topup user
      await (await credit.connect(otherAccount).topup(1000000000)).wait();
      expect(await credit.getCredit(otherAccount.address)).to.equal(1000000000);
      //grant role
      const X1000 = ethers.solidityPackedKeccak256(["string"], ["X1000"]);
      await (await bookie.setAddress(X1000, await x1000.getAddress())).wait();
      //open position
      await (
        await x1000
          .connect(otherAccount)
          .openLongPosition(
            otherAccount.address,
            ethers.encodeBytes32String("ETH"),
            100000000,
            1000000000,
            2539210000
          )
      ).wait();
    });
  });
});
