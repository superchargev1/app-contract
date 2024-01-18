import * as fs from "fs";
import path from "path";

const getContracts = () => {
  try {
    const contractPath = path.join(__dirname, "..", "contracts.json");
    return JSON.parse(fs.readFileSync(contractPath, "utf8"));
  } catch (error) {
    // console.log("Error: ", error);
    // throw error;
    return {}
  }
};

const writeContract = async (
  network: string,
  contractName: string,
  contractAddress: string
) => {
  const data = getContracts();

  if (!data[network]) {
    data[network] = {};
  }
  data[network][contractName] = contractAddress;
  const contractPath = path.join(__dirname, "..", "contracts.json");
  fs.writeFileSync(contractPath, JSON.stringify(data, null, "  "));
};

export { getContracts, writeContract };
