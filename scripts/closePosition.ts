import { ethers, network } from "hardhat";
import { getContracts } from "../utils/utils";

async function main() {
  const [deployer] = await ethers.getSigners();
  const provider = deployer.provider;
  const networkName = network.name;
  const batcher = new ethers.Wallet(
    "7efb17a6ddaf58b275c9a41a3ad6fc1390443a0e25737b066d41098e079d31f2",
    provider
  );
  const contracts = getContracts();
  const batchingFactory = await ethers.getContractFactory("Batching");
  const batch = new ethers.Contract(
    contracts[networkName]["Batching"],
    batchingFactory.interface,
    batcher
  );
  await (await batch.closeBatchPosition([29], [2310480000])).wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
