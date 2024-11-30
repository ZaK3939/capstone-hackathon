import { expect, mock, spyOn } from "bun:test";
import { ethers } from "ethers";
import { Address } from "viem";

// Global test utilities
global.setupTestProvider = () => {
  return new ethers.JsonRpcProvider("http://localhost:8545");
};

global.createMockWallet = () => {
  return ethers.Wallet.createRandom();
};

// Mock contract factory
export const createMockContract = (abi: any) => {
  return {
    interface: {
      format: () => abi,
    },
    address: ethers.hexlify(ethers.randomBytes(20)),
    on: mock(() => {}),
    removeAllListeners: mock(() => {}),
    isOperator: mock(() => {}),
    registerOperator: mock(() => {}),
    respondToTask: mock(() => {}),
  };
};

// Test constants
export const TEST_CONFIG = {
  rpcUrl: "http://localhost:8545",
  registryAddress: ethers.hexlify(ethers.randomBytes(20)) as Address,
  vaultAddress: ethers.hexlify(ethers.randomBytes(20)) as Address,
  stakeAmount: BigInt(1000),
  checkInterval: 1000,
};

export { expect, mock, spyOn };
