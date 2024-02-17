import { ethers, network } from "hardhat";
import { getContracts } from "../../utils/utils";

async function main() {
  try {
    const eventId = process.env.EVENT_ID;
    const threshold = process.env.THRESHOLD;
    if (!threshold || !eventId) {
      console.log("define the threshold and event id");
      return;
    }
    const [deployer] = await ethers.getSigners();
    const contracts = getContracts();
    const networkName = network.name;
    const predictMarketFactory = await ethers.getContractFactory(
      "PredictMarket"
    );
    const predictMarket = new ethers.Contract(
      contracts?.[networkName]?.["PredictMarket"],
      predictMarketFactory.interface,
      deployer
    );
    await (await predictMarket.setThreshold(eventId, threshold)).wait();
  } catch (error) {
    throw error;
  }
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((err) => {
    console.log("err: ", err);
    process.exit(1);
  });
