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

main("0xc615e3178a63BA2d720eb245f7872a129495C27C", 1000000000)
  .then(() => {
    process.exit(0);
  })
  .catch((err) => {
    console.log("err: ", err);
    process.exit(1);
  });
