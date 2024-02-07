import { ethers, network } from "hardhat";
import { getContracts } from "../../utils/utils";

async function main() {
  try {
    const burst = process.env.BURST;
    if (!burst) {
      console.log("define the burst");
      return;
    }
    const [deployer] = await ethers.getSigners();
    const contracts = getContracts();
    const networkName = network.name;
    const x1000Factory = await ethers.getContractFactory("X1000V2");
    const x1000V2 = new ethers.Contract(
      contracts?.[networkName]?.["X1000V2"],
      x1000Factory.interface,
      deployer
    );
    await (await x1000V2.setBurst(burst)).wait();
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
