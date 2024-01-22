import { ethers, network } from "hardhat";
import { ethers as etherLibs } from "ethers";
import { getContracts } from "../utils/utils";

async function main(userPk: string) {
  try {
    const [deployer] = await ethers.getSigners();
    console.log("network.config: ", network.config);

    const provider = new etherLibs.JsonRpcProvider(network.config.url);
    const user = new ethers.Wallet(userPk, provider);
    const networkName = network.name;
    const FactoryName = "MockUSDC";

    const contracts = getContracts();
    const Factory = await ethers.getContractFactory(FactoryName, deployer);
    //approve mockUSDC from deployer to the credit
    const mockUSDC = new ethers.Contract(
      contracts?.[networkName]?.[FactoryName],
      Factory.interface,
      deployer
    );
    const creditArtifact = await ethers.getContractFactory("Credit");
    const credit = new ethers.Contract(
      contracts?.[networkName]?.["Credit"],
      creditArtifact.interface,
      provider
    );
    await (
      await mockUSDC
        .connect(user)
        .approve(await credit.getAddress(), 1000000000)
    ).wait();
    //topup
    await (await credit.connect(user).topup(1000000000)).wait();
  } catch (error) {
    throw error;
  }
}

main("75e04dd9ceaec4619e519384d0f42cb3b9c36fe0eea1857b96d374c898a00340")
  .then(() => {
    process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
