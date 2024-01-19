import { ethers, network, upgrades } from "hardhat";
import { getContracts, writeContract } from "../../utils/utils";

async function main() {
  const [deployer] = await ethers.getSigners();
  const networkName = network.name;
  const FactoryName = "MockUSDC";

  const contracts = getContracts();
  const Factory = await ethers.getContractFactory(FactoryName, deployer);
  const initialSupply = 10000000000000;
  const contract = await Factory.deploy(initialSupply);
  await contract.waitForDeployment();
  writeContract(networkName, FactoryName, await contract.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
