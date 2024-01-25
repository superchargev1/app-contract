import { ethers, network } from "hardhat";
import { getContracts } from "../../utils/utils";

async function main() {
  const funding = process.env.FUNDING;
  if (!funding) {
    console.log("define the fund first");
    return;
  }
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
  await (
    await mockUSDC.connect(deployer).approve(await credit.getAddress(), funding)
  ).wait();
  //topup mockUSDC from deployer to credit
  await (await credit.connect(deployer).topupSystem(funding)).wait();
  //get credit platform balance
  const balance = await mockUSDC.balanceOf(await credit.getAddress());
  console.log("balance: ", balance);
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
