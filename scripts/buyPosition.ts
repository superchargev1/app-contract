import { ethers, network } from "hardhat";
import { getContracts } from "../utils/utils";

async function main(userPk: string) {
  const [deployer] = await ethers.getSigners();
  const provider = deployer.provider;
  const networkName = network.name;
  const contracts = getContracts();
  const user = new ethers.Wallet(userPk, provider);
  const predictFactory = await ethers.getContractFactory("PredictMarket");
  const predictMarket = new ethers.Contract(
    contracts[networkName]["PredictMarket"],
    predictFactory.interface,
    provider
  );
  const txhash = await (
    await predictMarket
      .connect(user)
      .buyPosition(BigInt(10000000), 461168601971587809319n)
  ).wait();
  console.log("txhash: ", txhash);
}

main("05da03320b3b4a107f0a340b74974596199219ff4031f9a22b85a7d6724ac33a")
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
