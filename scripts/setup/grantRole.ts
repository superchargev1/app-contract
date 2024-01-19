import { ethers, network } from "hardhat";
import { getContracts } from "../../utils/utils";

async function main() {
  const OPERATOR_ROLE = ethers.solidityPackedKeccak256(
    ["string"],
    ["OPERATOR_ROLE"]
  );
  const X1000_BATCHER_ROLE = ethers.solidityPackedKeccak256(
    ["string"],
    ["X1000_BATCHER_ROLE"]
  );
  const BATCHING = ethers.solidityPackedKeccak256(["string"], ["BATCHING"]);
  const X1000 = ethers.solidityPackedKeccak256(["string"], ["X1000"]);

  //operator and batcher
  const operator1 = "0xAF2D96d3FE6bA02a508aa136fA73216755D7e750"; //andrew
  const batcher = "0x431cEe0a7d44CbEB06e3C2f9e4A9335Fa5cb36e5";

  const [deployer] = await ethers.getSigners();
  const contracts = getContracts();
  const networkName = network.name;
  const FactoryName = "Bookie";
  const bookieArtifact = await ethers.getContractFactory(FactoryName);
  const bookie = new ethers.Contract(
    contracts?.[networkName]?.[FactoryName],
    bookieArtifact.interface,
    deployer
  );
  await (await bookie.grantRole(OPERATOR_ROLE, operator1)).wait();
  await (await bookie.grantRole(X1000_BATCHER_ROLE, batcher)).wait();
  await (
    await bookie.setAddress(BATCHING, contracts?.[networkName]?.["Batching"])
  ).wait();
  await (
    await bookie.setAddress(X1000, contracts?.[networkName]?.["X1000"])
  ).wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
