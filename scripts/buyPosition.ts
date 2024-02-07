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
      .buyPosition(BigInt(10000000), 424275113815578771491n)
  ).wait();
  console.log("txhash: ", txhash);
}

main("275f71e1edda45afd359d9a5035bd7872c49ae0a057a8fdcc41817d1bd8d578f")
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
