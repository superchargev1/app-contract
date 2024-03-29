import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

describe("X1000V2", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployX1000V2Fixture() {
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
    const X1000V2 = await ethers.getContractFactory("X1000V2", owner);
    const x1000V2 = await upgrades.deployProxy(
      X1000V2,
      [await bookie.getAddress(), await credit.getAddress()],
      {
        initializer: "initialize",
      }
    );
    await x1000V2.waitForDeployment();
    //deploy batching
    const Batching = await ethers.getContractFactory("Batching", owner);
    const batching = await upgrades.deployProxy(
      Batching,
      [await bookie.getAddress(), await x1000V2.getAddress()],
      {
        initializer: "initialize",
      }
    );
    await batching.waitForDeployment();
    return { x1000V2, bookie, mockUSDC, batching, credit, owner, otherAccount };
  }

  describe("Deployment", function () {
    it("Should deploy success", async function () {
      const {
        x1000V2,
        bookie,
        mockUSDC,
        batching,
        credit,
        owner,
        otherAccount,
      } = await loadFixture(deployX1000V2Fixture);
    });
    it("Should topup system success", async function () {
      const {
        x1000V2,
        bookie,
        mockUSDC,
        batching,
        credit,
        owner,
        otherAccount,
      } = await loadFixture(deployX1000V2Fixture);
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
    it.only("Should topup user success", async function () {
      const { x1000V2, bookie, mockUSDC, credit, owner, otherAccount } =
        await loadFixture(deployX1000V2Fixture);
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
      await (
        await mockUSDC.setTransferable(await credit.getAddress(), true)
      ).wait();
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
    it.only("Should open position success", async function () {
      const {
        x1000V2,
        bookie,
        mockUSDC,
        batching,
        credit,
        owner,
        otherAccount,
      } = await loadFixture(deployX1000V2Fixture);
      await (
        await mockUSDC
          .connect(owner)
          .approve(await credit.getAddress(), 1040685192888)
      ).wait();
      expect(
        await mockUSDC.allowance(
          await owner.getAddress(),
          await credit.getAddress()
        )
      ).to.eq(1040685192888);
      await (
        await mockUSDC.setTransferable(await credit.getAddress(), true)
      ).wait();
      await (await credit.topupSystem(1000000000000)).wait();
      expect(await credit.platformCredit()).to.equal(1000000000000);
      //fund mockUSDC to user
      await (
        await mockUSDC
          .connect(owner)
          .transfer(otherAccount.address, 2000000000000)
      ).wait();
      //approve mockUSDC to credit
      await (
        await mockUSDC
          .connect(otherAccount)
          .approve(await credit.getAddress(), 2000000000000)
      ).wait();
      //topup user
      await (await credit.connect(otherAccount).topup(2000000000000)).wait();
      expect(await credit.getCredit(otherAccount.address)).to.equal(
        2000000000000
      );
      //grant role
      const X1000 = ethers.solidityPackedKeccak256(["string"], ["X1000V2"]);
      const BATCHING = ethers.solidityPackedKeccak256(["string"], ["BATCHING"]);
      await (await bookie.setAddress(X1000, await x1000V2.getAddress())).wait();
      await (
        await bookie.grantRole(
          ethers.solidityPackedKeccak256(["string"], ["X1000_BATCHER_ROLE"]),
          otherAccount.address
        )
      ).wait();
      await (
        await bookie.grantRole(
          ethers.solidityPackedKeccak256(
            ["string"],
            ["X1000_BATCHER_CLOSE_ROLE"]
          ),
          otherAccount.address
        )
      ).wait();
      await (
        await bookie.setAddress(BATCHING, await batching.getAddress())
      ).wait();
      //open position
      // await (
      //   await x1000V2
      //     .connect(otherAccount)
      //     .openLongPositionV2(
      //       otherAccount.address,
      //       ethers.encodeBytes32String("ETH"),
      //       100000000,
      //       1000000000,
      //       2322420000,
      //       1
      //     )
      // ).wait();
      // await (
      //   await x1000V2
      //     .connect(otherAccount)
      //     .openShortPositionV2(
      //       otherAccount.address,
      //       ethers.encodeBytes32String("ETH"),
      //       100000000,
      //       1000000000,
      //       2322420000,
      //       1
      //     )
      // ).wait();
      // await (
      //   await x1000V2.connect(otherAccount).closePosition(1, 2320420000)
      // ).wait();
      // await (
      //   await x1000V2.connect(otherAccount).closePosition(2, 2323420000)
      // ).wait();
      const hash = ethers.keccak256(
        ethers.solidityPacked(
          ["address", "uint256"],
          [await x1000V2.getAddress(), 1]
        )
      );
      const message = ethers.getBytes(hash);
      console.log("otherAccount:", ethers.encodeBytes32String("BTC"));
      //set position
      await (
        await x1000V2
          .connect(owner)
          .setPosition(
            ethers.encodeBytes32String("BTC"),
            1,
            1,
            990000000,
            100000000,
            99000000000,
            42196900000,
            41859324800,
            42200791221,
            "0x12FE78Cb0D807f0Faf0E963F6C3663b818974a17"
          )
      ).wait();
      await (
        await x1000V2
          .connect(owner)
          .setPosition(
            ethers.encodeBytes32String("BTC"),
            1,
            1,
            9900000,
            100000000,
            990000000,
            42240000000,
            41902080000,
            42240139655,
            "0xd6f3FD60aFA52F48186cA4eB1d49bA59bC4014Ef"
          )
      ).wait();
      await (
        await x1000V2
          .connect(owner)
          .setPosition(
            ethers.encodeBytes32String("BTC"),
            1,
            1,
            99000000,
            100000000,
            9900000000,
            42146100000,
            41808931200,
            42146140039,
            "0x70f7acB809040F252e5cc4AdD5CA1c3326a192A0"
          )
      ).wait();
      await (
        await x1000V2
          .connect(owner)
          .setPosition(
            ethers.encodeBytes32String("BTC"),
            1,
            1,
            9900000,
            100000000,
            990000000,
            42049100000,
            41712707200,
            42049129549,
            "0xc615e3178a63BA2d720eb245f7872a129495C27C"
          )
      ).wait();
      await (
        await x1000V2
          .connect(owner)
          .setPosition(
            ethers.encodeBytes32String("BTC"),
            2,
            1,
            49500000,
            100000000,
            4950000000,
            42033800000,
            42370070400,
            42033769642,
            "0x3Fd90a476938128DAf98C51193ef7a6B139C974F"
          )
      ).wait();
      await (
        await x1000V2
          .connect(owner)
          .setPosition(
            ethers.encodeBytes32String("BTC"),
            1,
            1,
            49500000,
            100000000,
            4950000000,
            42043600000,
            41707251200,
            42043960856,
            "0x3Fd90a476938128DAf98C51193ef7a6B139C974F"
          )
      ).wait();
      await (
        await x1000V2
          .connect(owner)
          .setPosition(
            ethers.encodeBytes32String("BTC"),
            1,
            1,
            9930000,
            70000000,
            695100000,
            42060300000,
            41579610857,
            42060304527,
            "0x3Fd90a476938128DAf98C51193ef7a6B139C974F"
          )
      ).wait();
      // await (
      //   await batching.connect(otherAccount).openBatchPosition(
      //     [
      //       {
      //         account: otherAccount.address,
      //         poolId: ethers.encodeBytes32String("BTC"),
      //         value: 10000000,
      //         leverage: 100000000,
      //         price: 42049100000,
      //         isLong: true,
      //         plId: 1,
      //       },
      //     ],
      //     {
      //       value: 0,
      //     }
      //   )
      // ).wait();
      await (
        await batching
          .connect(otherAccount)
          .closeBatchPosition(
            [1, 2, 3, 4, 5, 6, 7],
            [
              42200000000, 42200000000, 42200000000, 42200000000, 42200000000,
              42200000000, 42200000000,
            ]
          )
      ).wait();
    });
  });
});
