import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

describe("PredictMarket", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployX1000V2Fixture() {
    const [owner, otherAccount, otherAccount1, otherAccount2] =
      await ethers.getSigners();

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
    //deploy PredictMarket
    const PredictMarket = await ethers.getContractFactory(
      "PredictMarket",
      owner
    );
    const predictMarket = await upgrades.deployProxy(
      PredictMarket,
      [await bookie.getAddress(), await credit.getAddress()],
      {
        initializer: "initialize",
      }
    );
    return {
      predictMarket,
      bookie,
      mockUSDC,
      credit,
      owner,
      otherAccount,
      otherAccount1,
      otherAccount2,
    };
  }

  describe("Deployment", function () {
    it("Should deploy success", async function () {
      const { predictMarket, bookie, mockUSDC, credit, owner, otherAccount } =
        await loadFixture(deployX1000V2Fixture);
    });
    it("Should topup system success", async function () {
      const { predictMarket, bookie, mockUSDC, credit, owner, otherAccount } =
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
      await (await credit.topupSystem(1000000000000)).wait();
      expect(await credit.platformCredit()).to.equal(1000000000000);
    });
    it("Should topup user success", async function () {
      const { predictMarket, bookie, mockUSDC, credit, owner, otherAccount } =
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
    it("Should create event success", async function () {
      const { predictMarket, bookie, mockUSDC, credit, owner, otherAccount } =
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
        await mockUSDC.connect(owner).transfer(otherAccount.address, 2000000000)
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
      //create event
      const eventId = 1;
      const startTime = Math.floor(Date.now() / 1000);
      const expireTime = Math.floor(new Date("2024-02-05").getTime() / 1000);
      const marketId = 1;
      await (
        await predictMarket.createEvent(eventId, startTime, expireTime, [
          marketId,
        ])
      ).wait();
    });
    it("Should open position success", async function () {
      const { predictMarket, bookie, mockUSDC, credit, owner, otherAccount } =
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
        await mockUSDC.connect(owner).transfer(otherAccount.address, 2000000000)
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
      const PREDICT_MARKET = ethers.solidityPackedKeccak256(
        ["string"],
        ["PREDICT_MARKET"]
      );
      await (
        await bookie.setAddress(
          PREDICT_MARKET,
          await predictMarket.getAddress()
        )
      ).wait();
      //create event
      const eventId = 1;
      const startTime = Math.floor(Date.now() / 1000);
      const expireTime = Math.floor(new Date("2024-02-05").getTime() / 1000);
      console.log("expireTime: ", expireTime);
      const marketId = 1;
      await (
        await predictMarket.createEvent(eventId, startTime, expireTime, [
          marketId,
        ])
      ).wait();
      //buy position
      const oddId = 1;
      let _id = BigInt(eventId);
      _id = (_id << BigInt(32)) + BigInt(marketId);
      _id = (_id << BigInt(32)) + BigInt(oddId);
      const outcomeId = ethers.parseEther(ethers.formatEther(_id));

      await (
        await predictMarket
          .connect(otherAccount)
          .buyPosition(10000000, outcomeId)
      ).wait();
      const position = await predictMarket.getPosition(1);
      console.log("position: ", position);
      expect(position[5]).to.equal(1);
    });
    it.only("Should resolve initial success", async function () {
      const {
        predictMarket,
        bookie,
        mockUSDC,
        credit,
        owner,
        otherAccount,
        otherAccount1,
        otherAccount2,
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
      await (
        await mockUSDC.setTransferable(await credit.getAddress(), true)
      ).wait();
      await (await credit.topupSystem(1000000000000)).wait();
      expect(await credit.platformCredit()).to.equal(1000000000000);
      //fund mockUSDC to user
      await (
        await mockUSDC.connect(owner).transfer(otherAccount.address, 2000000000)
      ).wait();
      //approve mockUSDC to credit
      await (
        await mockUSDC
          .connect(otherAccount)
          .approve(await credit.getAddress(), 2000000000)
      ).wait();
      //topup user
      await (await credit.connect(otherAccount).topup(2000000000)).wait();
      expect(await credit.getCredit(otherAccount.address)).to.equal(2000000000);
      await (
        await mockUSDC
          .connect(owner)
          .transfer(otherAccount1.address, 2000000000)
      ).wait();
      //approve mockUSDC to credit
      await (
        await mockUSDC
          .connect(otherAccount1)
          .approve(await credit.getAddress(), 2000000000)
      ).wait();
      //topup user
      await (await credit.connect(otherAccount1).topup(2000000000)).wait();
      expect(await credit.getCredit(otherAccount1.address)).to.equal(
        2000000000
      );
      await (
        await mockUSDC
          .connect(owner)
          .transfer(otherAccount2.address, 20000000000)
      ).wait();
      //approve mockUSDC to credit
      await (
        await mockUSDC
          .connect(otherAccount2)
          .approve(await credit.getAddress(), 20000000000)
      ).wait();
      //topup user
      await (await credit.connect(otherAccount2).topup(20000000000)).wait();
      expect(await credit.getCredit(otherAccount2.address)).to.equal(
        20000000000
      );
      //grant role
      const PREDICT_MARKET = ethers.solidityPackedKeccak256(
        ["string"],
        ["PREDICT_MARKET"]
      );
      const RESOLVER_ROLE = ethers.solidityPackedKeccak256(
        ["string"],
        ["RESOLVER_ROLE"]
      );
      const BOOKER_ROLE = ethers.solidityPackedKeccak256(
        ["string"],
        ["BOOKER_ROLE"]
      );
      await (
        await bookie.setAddress(
          PREDICT_MARKET,
          await predictMarket.getAddress()
        )
      ).wait();
      await (await bookie.grantRole(RESOLVER_ROLE, owner.address)).wait();
      await (await bookie.grantRole(BOOKER_ROLE, owner.address)).wait();
      //create event
      const eventId = 25;
      const startTime = Math.floor(Date.now() / 1000);
      const expireTime = Math.floor(new Date("2024-02-25").getTime() / 1000);
      console.log("expireTime: ", expireTime);
      await (
        await predictMarket.createEvent(
          eventId,
          startTime,
          expireTime,
          1000000000000,
          [461168601971587809319n, 461168601971587809320n]
        )
      ).wait();
      //buy in blinding bid
      //resolve initial
      await (await predictMarket.resolveInitializePool(eventId)).wait();
      expect(((await predictMarket.getEventData(eventId)) as any)[2]).to.equal(
        2
      );
      const message1 = ethers.getBytes(
        ethers.keccak256(
          ethers.solidityPacked(
            ["address", "address", "uint88", "uint256", "uint256"],
            [
              await predictMarket.getAddress(),
              otherAccount.address,
              1000000000,
              461168601971587809319n,
              0,
            ]
          )
        )
      );
      const signature1 = await owner.signMessage(message1);
      await (
        await predictMarket
          .connect(otherAccount)
          .buyPosition(1000000000, 461168601971587809319n, 0, signature1)
      ).wait();
      //buy the signature
      const message = ethers.getBytes(
        ethers.keccak256(
          ethers.solidityPacked(
            ["address", "address", "uint88", "uint256", "uint256"],
            [
              await predictMarket.getAddress(),
              otherAccount.address,
              100000000,
              461168601971587809320n,
              0,
            ]
          )
        )
      );
      const signature = await owner.signMessage(message);
      await (
        await predictMarket
          .connect(otherAccount)
          .buyPosition(100000000, 461168601971587809320n, 0, signature)
      ).wait();
      //get the ticketId
      const ticketId = ethers.keccak256(
        ethers.solidityPacked(
          ["address", "uint256"],
          [otherAccount.address, 461168601971587809320n]
        )
      );
      //add more liquidity to sell previous position
      const message2 = ethers.getBytes(
        ethers.keccak256(
          ethers.solidityPacked(
            ["address", "address", "uint88", "uint256", "uint256"],
            [
              await predictMarket.getAddress(),
              otherAccount1.address,
              100000000,
              461168601971587809320n,
              0,
            ]
          )
        )
      );
      const signature2 = await owner.signMessage(message2);
      await (
        await predictMarket
          .connect(otherAccount1)
          .buyPosition(100000000, 461168601971587809320n, 0, signature2)
      ).wait();
      const message3 = ethers.getBytes(
        ethers.keccak256(
          ethers.solidityPacked(
            ["address", "address", "uint88", "uint256", "uint256"],
            [
              await predictMarket.getAddress(),
              otherAccount2.address,
              10000000000,
              461168601971587809320n,
              0,
            ]
          )
        )
      );
      const signature3 = await owner.signMessage(message3);
      await (
        await predictMarket
          .connect(otherAccount2)
          .buyPosition(10000000000, 461168601971587809320n, 0, signature3)
      ).wait();
      const messageSell = ethers.getBytes(
        ethers.keccak256(
          ethers.solidityPacked(
            ["address", "address", "uint256", "uint88", "uint256[]"],
            [
              await predictMarket.getAddress(),
              otherAccount.address,
              ticketId,
              995000000,
              [2],
            ]
          )
        )
      );

      const signatureSell = await owner.signMessage(messageSell);
      await (
        await predictMarket
          .connect(otherAccount)
          .sellPosition(ticketId, 995000000, [2], signatureSell)
      ).wait();
      //get the ticket of otherAccount1
      const ticketId1 = ethers.keccak256(
        ethers.solidityPacked(
          ["address", "uint256"],
          [otherAccount1.address, 461168601971587809320n]
        )
      );
      const messageSell1 = ethers.getBytes(
        ethers.keccak256(
          ethers.solidityPacked(
            ["address", "address", "uint256", "uint88", "uint256[]"],
            [
              await predictMarket.getAddress(),
              otherAccount1.address,
              ticketId1,
              497000000,
              [3],
            ]
          )
        )
      );

      const signatureSell1 = await owner.signMessage(messageSell1);
      await (
        await predictMarket
          .connect(otherAccount1)
          .sellPosition(ticketId1, 497000000, [3], signatureSell1)
      ).wait();

      //get the ticket of otherAccount2
      const ticketId2 = ethers.keccak256(
        ethers.solidityPacked(
          ["address", "uint256"],
          [otherAccount2.address, 461168601971587809320n]
        )
      );
      const messageSell2 = ethers.getBytes(
        ethers.keccak256(
          ethers.solidityPacked(
            ["address", "address", "uint256", "uint88", "uint256[]"],
            [
              await predictMarket.getAddress(),
              otherAccount2.address,
              ticketId2,
              9900000000,
              [4],
            ]
          )
        )
      );

      const signatureSell2 = await owner.signMessage(messageSell2);
      await (
        await predictMarket
          .connect(otherAccount2)
          .sellPosition(ticketId2, 9900000000, [4], signatureSell2)
      ).wait();
    });
    it("Should buy position afer resolve initial success", async function () {
      const { predictMarket, bookie, mockUSDC, credit, owner, otherAccount } =
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
        await mockUSDC.connect(owner).transfer(otherAccount.address, 2000000000)
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
      const PREDICT_MARKET = ethers.solidityPackedKeccak256(
        ["string"],
        ["PREDICT_MARKET"]
      );
      const RESOLVER_ROLE = ethers.solidityPackedKeccak256(
        ["string"],
        ["RESOLVER_ROLE"]
      );
      await (
        await bookie.setAddress(
          PREDICT_MARKET,
          await predictMarket.getAddress()
        )
      ).wait();
      await (await bookie.grantRole(RESOLVER_ROLE, owner.address)).wait();
      //create event
      const eventId = 1;
      const startTime = Math.floor(Date.now() / 1000);
      const expireTime = Math.floor(new Date("2024-02-05").getTime() / 1000);
      console.log("expireTime: ", expireTime);
      const marketId = 1;
      await (
        await predictMarket.createEvent(eventId, startTime, expireTime, [
          marketId,
        ])
      ).wait();
      //buy position
      const oddId = 1;
      let _id = BigInt(eventId);
      _id = (_id << BigInt(32)) + BigInt(marketId);
      _id = (_id << BigInt(32)) + BigInt(oddId);
      const outcomeId = ethers.parseEther(ethers.formatEther(_id));
      await (
        await predictMarket
          .connect(otherAccount)
          .buyPosition(10000000, outcomeId)
      ).wait();
      expect(((await predictMarket.getPosition(1)) as any)[5]).to.equal(1);
      //resolve initial
      await (await predictMarket.resolveInitializePool(eventId)).wait();
      expect(((await predictMarket.getEventData(eventId)) as any)[2]).to.equal(
        2
      );
      await (
        await predictMarket
          .connect(otherAccount)
          .buyPosition(10000000, outcomeId)
      ).wait();
      const position = await predictMarket.getPosition(2);
      console.log("position: ", position);
    });
  });
});
