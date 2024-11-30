import { Address, Hash } from "viem";

// Core Types
export interface PoolMetrics {
  volumeUSD: number;
  tvlUSD: number;
  priceImpact: number;
  swapCount: number;
  failedTxCount: number;
  gasUsed: bigint;
}

export interface RiskTask {
  hook: Address;
  taskCreatedBlock: number;
  poolId: Hash;
  checkpointId: number;
}

export interface TaskResponse {
  metrics: PoolMetrics;
  riskScore: number;
  timestamp: number;
  signature: string;
}

export interface IServiceConfig {
  registryAddress: Address;
  vaultAddress: Address;
  stakeAmount: bigint;
  rpcUrl: string;
  checkInterval: number;
}

// Contract Event Types
export interface NewTaskEvent {
  taskId: number;
  task: RiskTask;
}

export interface TaskResponseEvent {
  taskId: number;
  operator: Address;
  response: TaskResponse;
}

// Operator State
export type OperatorState = "STARTING" | "ACTIVE" | "PAUSED" | "ERROR";

// Service Interface
export interface IRiskService {
  start(): Promise<void>;
  stop(): Promise<void>;
  getState(): OperatorState;
  submitResponse(taskId: number, response: TaskResponse): Promise<boolean>;
}
