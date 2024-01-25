import { ethers, network, upgrades } from "hardhat";
import { getContracts, writeContract } from "../../utils/utils";

async function main() {
  const [deployer] = await ethers.getSigners();
  const networkName = network.name;
  const FactoryName = "Batching";

  const contracts = getContracts();
  console.log("network.name: ", network.name);
  if (
    !contracts?.[networkName]["X1000V2"] ||
    !contracts?.[networkName]["Bookie"]
  ) {
    console.log("Deploy bookie and X1000V2 first");
    return;
  }
  let proxy: any = contracts?.[networkName]?.[FactoryName];
  if (!proxy) {
    console.log(
      "Deploying contract Batching: ",
      contracts?.[networkName]["X1000V2"]
    );
    const Factory = await ethers.getContractFactory(FactoryName, deployer);
    const contract = await upgrades.deployProxy(
      Factory,
      [contracts?.[networkName]["Bookie"], contracts?.[networkName]["X1000V2"]],
      {
        initializer: "initialize",
      }
    );
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
