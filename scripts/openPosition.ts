import { ethers, network } from "hardhat";
import { getContracts } from "../utils/utils";
import { getBytes, keccak256, solidityPacked } from "ethers";

async function main() {
  const [deployer] = await ethers.getSigners();
  const provider = deployer.provider;
  const networkName = network.name;
  const batcher = new ethers.Wallet(
    "7efb17a6ddaf58b275c9a41a3ad6fc1390443a0e25737b066d41098e079d31f2",
    provider
  );
  const contracts = getContracts();
  const batchingFactory = await ethers.getContractFactory("Batching");
  const batch = new ethers.Contract(
    contracts[networkName]["Batching"],
    batchingFactory.interface,
    batcher
  );
  const x1000V2Factory = await ethers.getContractFactory("X1000V2");
  const x1000V2 = new ethers.Contract(
    contracts[networkName]["X1000V2"],
    x1000V2Factory.interface,
    deployer
  );
  //   const txh = await (
  //     await x1000V2.openLongPositionV2(
  //       "0xf9F689367990f981BCD267FB1A4c45f63B6Bd7b1",
  //       "0x4554480000000000000000000000000000000000000000000000000000000000",
  //       10000000,
  //       100000000,
  //       2208480000,
  //       2
  //     )
  //   ).wait();
  //   console.log("txh: ", txh);
  const hash = keccak256(
    solidityPacked(["address", "uint256"], [await x1000V2.getAddress(), 3])
  );
  const message = getBytes(hash);
  const signature = await batcher.signMessage(message);

  const txh = await (
    await batch.openBatchPosition(
      [
        {
          account: "0xf9F689367990f981BCD267FB1A4c45f63B6Bd7b1",
          poolId:
            "0x4554480000000000000000000000000000000000000000000000000000000000",
          value: 10000000,
          leverage: 100000000,
          price: 2208480000,
          isLong: true,
          plId: 3,
          signature,
        },
      ],
      {
        value: 0,
      }
    )
  ).wait();
  console.log("txh: ", txh);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
