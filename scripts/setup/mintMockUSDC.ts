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

main("0xE135c2f9E72BB0cC45a62B45F620D1088dd324f0", 1000000000)
  .then(() => {
    process.exit(0);
  })
  .catch((err) => {
    console.log("err: ", err);
    process.exit(1);
  });
