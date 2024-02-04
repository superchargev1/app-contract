import { ethers, network } from "hardhat";
import { getContracts } from "../../utils/utils";

async function main(address: string) {
  const [deployer] = await ethers.getSigners();
  console.log("deployer: ", deployer.address);

  const networkName = network.name;
  const FactoryName = "MockUSDC";
  const contracts = getContracts();
  const Factory = await ethers.getContractFactory(FactoryName);
  const mockUSDC = new ethers.Contract(
    contracts?.[networkName]?.[FactoryName],
    Factory.interface,
    deployer
  );
  //transfer mockUSDC to the deployer
  // await (await mockUSDC.transfer(deployer.address, funding)).wait();
  //approve mockUSDC from deployer to the credit
  const creditArtifact = await ethers.getContractFactory("Credit");
  const credit = new ethers.Contract(
    contracts?.[networkName]?.["Credit"],
    creditArtifact.interface,
    deployer
  );
  //setTransferable
  await (
    await mockUSDC.connect(deployer).setTransferable(address, true)
  ).wait();
}

main("0x83bF30594abD39FaA15CCF58937CAF1F0F530717")
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
