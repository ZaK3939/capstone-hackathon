import { ethers } from "ethers";
import * as dotenv from "dotenv";
import * as fs from "fs";
import * as path from "path";
dotenv.config();

// Check env
if (!Object.keys(process.env).length) {
  throw new Error("process.env object is empty");
}

// Parse command line arguments
const args = process.argv.slice(2);
if (args.length < 1) {
  console.error("Usage: ts-node createMetricsTasks.ts <hook-address>");
  process.exit(1);
}

const hookAddress = args[0];
if (!ethers.isAddress(hookAddress)) {
  console.error("Invalid hook address provided");
  process.exit(1);
}

// Setup env variables
const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);
let chainId = 31337;

// Load deployment data
const avsDeploymentData = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, `../deployments/hello-world/${chainId}.json`), "utf8"),
);

const serviceManagerAddress = avsDeploymentData.addresses.uniGuardServiceManager;
const serviceManagerABI = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, "../abis/UniGuardServiceManager.json"), "utf8"),
);

const serviceManager = new ethers.Contract(serviceManagerAddress, serviceManagerABI, wallet);

function generateMetricsTaskName(hookAddress: string): string {
  const timestamp = Date.now();
  const formattedAddr = ethers.getAddress(hookAddress.padEnd(42, "0"));
  return `metrics_${formattedAddr}_${timestamp}`;
}

async function createMetricsTask(hookAddress: string) {
  try {
    const taskName = generateMetricsTaskName(hookAddress);
    const tx = await serviceManager.createNewTask(taskName);
    const receipt = await tx.wait();
    console.log(`Metrics task created for hook ${hookAddress}, tx: ${receipt.hash}`);
  } catch (error) {
    console.error("Error creating metrics task:", error);
  }
}

function startMetricsTasks() {
  console.log(`Starting metrics tasks for hook: ${hookAddress}`);

  setInterval(() => {
    console.log(`Creating metrics task for hook: ${hookAddress}`);
    createMetricsTask(hookAddress);
  }, 24000);
}

startMetricsTasks();
