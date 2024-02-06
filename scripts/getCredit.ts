import { ethers, network } from "hardhat";
import { getContracts } from "../utils/utils";

async function main(address: string) {
  const [deployer] = await ethers.getSigners();
  const provider = deployer.provider;
  const networkName = network.name;
  const contracts = getContracts();
  const creditFactory = await ethers.getContractFactory("Credit");
  const credit = new ethers.Contract(
    contracts[networkName]["Credit"],
    creditFactory.interface,
    provider
  );
  const credits = await credit.getCredit(address);
  console.log(credits);
}

main("0x509b19De20cAa730F4e2F2e4A9014B76dD501659")
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
