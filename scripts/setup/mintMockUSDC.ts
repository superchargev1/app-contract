import { ethers, network } from "hardhat";
import { getContracts } from "../../utils/utils";

async function main(address: string, funding: number) {
  const [deployer] = await ethers.getSigners();
  const networkName = network.name;
  const FactoryName = "MockUSDC";
  const contracts = getContracts();
  const Factory = await ethers.getContractFactory(FactoryName);
  const mockUSDC = new ethers.Contract(
    contracts?.[networkName]?.[FactoryName],
    Factory.interface,
    deployer
  );
  await (await mockUSDC.transfer(address, funding)).wait();
}

main("0x0D1bF830D7dD8A70E074973795B827B0E9ca28ea", 1000000000)
  .then(() => {
    process.exit(0);
  })
  .catch((err) => {
    console.log("err: ", err);
    process.exit(1);
  });
