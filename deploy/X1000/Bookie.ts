import { ethers, network, upgrades } from "hardhat";
import { getContracts, writeContract } from "../../utils/utils";

async function main() {
  const [deployer] = await ethers.getSigners();
  const networkName = network.name;
  const FactoryName = "Bookie";

  const contracts = getContracts();
  let proxy: any = contracts?.[networkName]?.[FactoryName];
  if (!proxy) {
    console.log("Deploying contract");
    const Factory = await ethers.getContractFactory(FactoryName, deployer);
    const contract = await upgrades.deployProxy(Factory, [], {
      initializer: "initialize",
    });
    await contract.waitForDeployment();
    proxy = await contract.getAddress();
    const implemented = await upgrades.erc1967.getImplementationAddress(proxy);

    writeContract(networkName, FactoryName, proxy);
    writeContract(networkName, FactoryName + "-implemented", implemented);
  } else {
    const oldImplemented = await upgrades.erc1967.getImplementationAddress(
      proxy
    );
    const Factory = await ethers.getContractFactory(FactoryName, deployer);
    const contract = await upgrades.upgradeProxy(proxy, Factory);
    const implemented = await upgrades.erc1967.getImplementationAddress(proxy);
    writeContract(
      networkName,
      FactoryName + "-implemented-old",
      oldImplemented
    );
    writeContract(networkName, FactoryName + "-implemented", implemented);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
