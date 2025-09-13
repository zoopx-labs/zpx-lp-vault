import { ethers } from 'ethers';
import * as fs from 'fs';
import dotenv from 'dotenv';
dotenv.config();

async function main() {
  const provider = new ethers.JsonRpcProvider(process.env.RPC_URL || 'http://localhost:8545');
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY || '', provider);

  const stakeAbi = JSON.parse(fs.readFileSync('../out/abi/MockERC20.json', 'utf8'));
  const stakeFactory = new ethers.ContractFactory(stakeAbi, fs.readFileSync('../out/MockERC20.bin', 'utf8'), wallet as any);
  const stake = await stakeFactory.deploy();
  await stake.waitForDeployment();
  const reward = await stakeFactory.deploy();
  await reward.waitForDeployment();

  console.log('stake:', stake.target);
  console.log('reward:', reward.target);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
