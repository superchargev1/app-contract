import { ethers, network } from "hardhat";
import { getContracts } from "../../utils/utils";

async function main() {
  try {
    const pnlFee = process.env.PNL_FEE;
    if (!pnlFee) {
      console.log("define the pnl fee with base 1000");
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
    await (await predictMarket.setPnlFee(pnlFee)).wait();
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
