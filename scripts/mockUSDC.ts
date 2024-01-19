import { ethers, network } from "hardhat";
import { getContracts } from "../utils/utils";

const WEI6 = 1000000;
async function main(address: string) {
  const [deployer] = await ethers.getSigners();
  const networkName = network.name;
  const FactoryName = "MockUSDC";

  const contracts = getContracts();
  const Factory = await ethers.getContractFactory(FactoryName, deployer);
  const mockUSDC = new ethers.Contract(
    contracts?.[networkName]?.[FactoryName],
    Factory.interface,
    deployer
  );
  await (await mockUSDC.mint(address, 1000 * WEI6)).wait();
}

main("")
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
