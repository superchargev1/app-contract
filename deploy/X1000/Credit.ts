import { ethers, network, upgrades } from "hardhat";
import { getContracts, writeContract } from "../../utils/utils";

async function main() {
  const minTopup = process.env.MIN_TOPUP;
  const maxWithdraw = process.env.MAX_WITHDRAW;
  if (!minTopup || !maxWithdraw) {
    console.log("Please set MIN_TOPUP and MAX_WITHDRAW");
    return;
  }
  const [deployer] = await ethers.getSigners();
  const networkName = network.name;
  const FactoryName = "Credit";

  const contracts = getContracts();
  let proxy: any = contracts?.[networkName]?.[FactoryName];
  if (!proxy) {
    console.log("Deploying contract");
    const Factory = await ethers.getContractFactory(FactoryName, deployer);
    const contract = await upgrades.deployProxy(
      Factory,
      [
        contracts?.[networkName]["Bookie"],
        contracts?.[networkName]["MockUSDC"],
        minTopup,
        maxWithdraw,
      ],
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
