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
  const X1000_BATCHER_BURN_ROLE = ethers.solidityPackedKeccak256(
    ["string"],
    ["X1000_BATCHER_BURN_ROLE"]
  );
  const X1000_BATCHER_CLOSE_ROLE = ethers.solidityPackedKeccak256(
    ["string"],
    ["X1000_BATCHER_CLOSE_ROLE"]
  );
  const BATCHING = ethers.solidityPackedKeccak256(["string"], ["BATCHING"]);
  const X1000 = ethers.solidityPackedKeccak256(["string"], ["X1000V2"]);

  //operator and batcher
  const operator1 = "0xAF2D96d3FE6bA02a508aa136fA73216755D7e750"; //andrew
  const batcher = "0x431cEe0a7d44CbEB06e3C2f9e4A9335Fa5cb36e5";
  const batcher2 = "0x123D95d5C0DC9beD62C43DC4b94d45163c0F4ebe";
  const batcher3 = "0xaF478a9389D103FDCe605F87E38ad82c6357715F";
  const batcherBurn = "0x4e4BC766F24927E53E58E840577511d72d19707d";
  const batcherBurn2 = "0x818BEddcb9B0C2Fd99653e39D43f16956B82D440";
  const batcherClose = "0x59Ac71331D0431F90381da339A434adD3d49A86a";
  const batcherClose2 = "0x60dcD17C44D905967a704F0091396f6EbFa2fb8F";
  const batcherClose3 = "0x34d08Bcb36895c9d7B2b116Cdd1A0263Bd42a398";

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
  await (await bookie.grantRole(X1000_BATCHER_ROLE, batcher2)).wait();
  await (await bookie.grantRole(X1000_BATCHER_ROLE, batcher3)).wait();
  await (await bookie.grantRole(X1000_BATCHER_BURN_ROLE, batcherBurn)).wait();
  await (await bookie.grantRole(X1000_BATCHER_BURN_ROLE, batcherBurn2)).wait();
  await (await bookie.grantRole(X1000_BATCHER_CLOSE_ROLE, batcherClose)).wait();
  await (
    await bookie.grantRole(X1000_BATCHER_CLOSE_ROLE, batcherClose2)
  ).wait();
  await (
    await bookie.grantRole(X1000_BATCHER_CLOSE_ROLE, batcherClose3)
  ).wait();
  await (
    await bookie.setAddress(BATCHING, contracts?.[networkName]?.["Batching"])
  ).wait();
  await (
    await bookie.setAddress(X1000, contracts?.[networkName]?.["X1000V2"])
  ).wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
