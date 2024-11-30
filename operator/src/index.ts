import { Address } from "viem";
import { RiskService } from "./risk";
import { IServiceConfig } from "./types";
import * as dotenv from "dotenv";
const fs = require("fs");
const path = require("path");

dotenv.config();

// Load config from env
const config: IServiceConfig = {
  registryAddress: process.env.REGISTRY_ADDRESS! as Address,
  vaultAddress: process.env.VAULT_ADDRESS! as Address,
  stakeAmount: BigInt(process.env.STAKE_AMOUNT || "0"),
  rpcUrl: process.env.RPC_URL!,
  checkInterval: parseInt(process.env.CHECK_INTERVAL || "24000"),
};

// Load ABIs
const serviceManagerABI = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, "../contracts/abis/ServiceManager.json"), "utf8"),
);

const registryABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, "../contracts/abis/HookRegistry.json"), "utf8"));

// Initialize and start service
async function main() {
  const service = new RiskService(config, serviceManagerABI, registryABI);

  // Handle shutdown
  process.on("SIGINT", async () => {
    console.log("Shutting down...");
    await service.stop();
    process.exit(0);
  });

  // Start service
  try {
    await service.start();
  } catch (error) {
    console.error("Failed to start service:", error);
    process.exit(1);
  }
}

main().catch(console.error);
