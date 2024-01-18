import { ethers, upgrades, run, network } from "hardhat";
import 'dotenv/config'
import crypto from "crypto";
import { Wallet } from "ethers";
import { getContracts, writeContract } from "../utils/utils";

async function main() {
  const [deployer] = await ethers.getSigners();
  const contracts = getContracts()
  const networkName = network.name
  const FactoryName = process.env.CONTRACT as string
  let proxy: any = contracts?.[networkName]?.[FactoryName]

  if (!proxy) {
    console.log("Contract Not Found")
    console.log("CONTRACT=[ContractName] yarn hardhat --network goerli run deploy/verify.ts")
    return
  }

  await run("verify:verify", {
    address: proxy
  })
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});