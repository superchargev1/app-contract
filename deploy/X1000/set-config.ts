import { ethers, upgrades, network } from "hardhat";
import 'dotenv/config'
import crypto from "crypto";
import { Wallet } from "ethers";
import { getBytes, keccak256, parseEther, solidityPackedKeccak256, toUtf8Bytes, ZeroAddress, formatEther } from "ethers";
const operatorRole = keccak256(toUtf8Bytes('OPERATOR_ROLE'))
import { getContracts, writeContract } from "../../utils/utils";

async function main() {
    const [deployer] = await ethers.getSigners();
    const contracts = getContracts()
    const networkName = network.name
    const FactoryName = "X1000"
    let proxy: any = contracts?.[networkName]?.[FactoryName]

    console.log("DONE");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});