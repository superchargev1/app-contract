import { ethers, network, upgrades } from "hardhat";
import { getContracts } from "../../utils/utils";

async function main() {
  //   const [deployer] = await ethers.getSigners();
  //   const contracts = getContracts();
  //   const networkName = network.name;
  const FactoryName = "Credit";
  const creditArtifact = await ethers.getContractFactory(FactoryName);
  await upgrades.forceImport(
    "0x6f29dBABdC8Ce40493E6d7E1FFBCBE86bd84c417",
    creditArtifact,
    {
      kind: "transparent",
    }
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
