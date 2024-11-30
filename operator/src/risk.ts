import { ethers } from "ethers";
import { IRiskService, IServiceConfig, OperatorState, PoolMetrics, RiskTask, TaskResponse } from "./types";
import { calculateRiskScore, detectAnomalies } from "./metrics";

export class RiskService implements IRiskService {
  private state: OperatorState = "STARTING";
  private provider: ethers.Provider;
  private wallet: ethers.Wallet;
  private serviceManager: ethers.Contract;
  private registry: ethers.Contract;
  private currentTask?: RiskTask;

  constructor(
    private config: IServiceConfig,
    serviceManagerABI: any,
    registryABI: any,
  ) {
    this.provider = new ethers.JsonRpcProvider(config.rpcUrl);
    this.wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, this.provider);

    this.serviceManager = new ethers.Contract(config.registryAddress, serviceManagerABI, this.wallet);

    this.registry = new ethers.Contract(config.registryAddress, registryABI, this.wallet);
  }

  async start(): Promise<void> {
    try {
      // Register as operator if needed
      const isRegistered = await this.registry.isOperator(this.wallet.address);
      if (!isRegistered) {
        await this.registerAsOperator();
      }

      // Start listening for tasks
      this.serviceManager.on("NewRiskTaskCreated", this.handleNewTask.bind(this));

      this.state = "ACTIVE";
      console.log("Risk service started");
    } catch (error) {
      this.state = "ERROR";
      console.error("Failed to start service:", error);
      throw error;
    }
  }

  async stop(): Promise<void> {
    this.serviceManager.removeAllListeners();
    this.state = "PAUSED";
  }

  getState(): OperatorState {
    return this.state;
  }

  private async registerAsOperator(): Promise<void> {
    const tx = await this.registry.registerOperator({
      value: this.config.stakeAmount,
    });
    await tx.wait();
    console.log("Registered as operator");
  }

  private async handleNewTask(taskId: number, task: RiskTask) {
    try {
      // Collect metrics
      const metrics = await this.collectMetrics(task);

      // Calculate risk score
      const riskScore = calculateRiskScore(metrics);

      // Check for anomalies
      const anomalies = detectAnomalies(metrics);
      if (anomalies.length > 0) {
        console.log("Detected anomalies:", anomalies);
      }

      // Create and sign response
      const response = await this.createSignedResponse(task, metrics, riskScore);

      // Submit response
      await this.submitResponse(taskId, response);
    } catch (error) {
      console.error("Error handling task:", error);
    }
  }

  private async collectMetrics(task: RiskTask): Promise<PoolMetrics> {
    // TODO: Implement actual metric collection
    return {
      volumeUSD: 500000,
      tvlUSD: 1000000,
      priceImpact: 0.02,
      swapCount: 500,
      failedTxCount: 5,
      gasUsed: BigInt(1000000),
    };
  }

  private async createSignedResponse(task: RiskTask, metrics: PoolMetrics, riskScore: number): Promise<TaskResponse> {
    const messageHash = ethers.solidityPackedKeccak256(
      ["address", "bytes32", "uint256", "uint256"],
      [task.hook, task.poolId, task.checkpointId, riskScore],
    );

    const signature = await this.wallet.signMessage(ethers.getBytes(messageHash));

    return {
      metrics,
      riskScore,
      timestamp: Date.now(),
      signature,
    };
  }

  async submitResponse(taskId: number, response: TaskResponse): Promise<boolean> {
    try {
      const tx = await this.serviceManager.respondToTask(
        this.currentTask!,
        taskId,
        response.riskScore,
        response.signature,
      );

      await tx.wait();
      console.log(`Response submitted for task ${taskId}`);
      return true;
    } catch (error) {
      console.error("Failed to submit response:", error);
      return false;
    }
  }
}
