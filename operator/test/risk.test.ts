import { describe, test, beforeAll, beforeEach, afterEach, expect, mock } from "bun:test";
import { ethers } from "ethers";
import { RiskService } from "../src/risk";
import { TEST_CONFIG, createMockContract } from "./setup";
import type { RiskTask } from "../src/types";

describe("RiskService", () => {
  let riskService: RiskService;
  let serviceManagerMock: any;
  let registryMock: any;
  let testWallet: ethers.Wallet;

  const testTask: RiskTask = {
    hook: "0x1234567890123456789012345678901234567890",
    taskCreatedBlock: 100,
    poolId: ethers.id("test-pool"),
    checkpointId: 1,
  };

  beforeAll(() => {
    // Create test wallet
    testWallet = ethers.Wallet.createRandom();
    process.env.PRIVATE_KEY = testWallet.privateKey;
  });

  beforeEach(() => {
    // Setup mocks
    serviceManagerMock = createMockContract([]);
    registryMock = createMockContract([]);

    // Create service instance
    riskService = new RiskService(TEST_CONFIG, serviceManagerMock, registryMock);
  });

  afterEach(() => {
    // Cleanup
    mock.restore();
  });

  describe("Initialization", () => {
    test("starts in STARTING state", () => {
      expect(riskService.getState()).toBe("STARTING");
    });

    test("registers as operator if not registered", async () => {
      // Setup mock
      registryMock.isOperator.mockImplementation(() => false);
      const registerSpy = spyOn(registryMock, "registerOperator");

      await riskService.start();

      expect(registerSpy).toHaveBeenCalled();
    });

    test("skips registration if already registered", async () => {
      registryMock.isOperator.mockImplementation(() => true);
      const registerSpy = spyOn(registryMock, "registerOperator");

      await riskService.start();

      expect(registerSpy).not.toHaveBeenCalled();
    });
  });

  describe("Task Processing", () => {
    beforeEach(async () => {
      registryMock.isOperator.mockImplementation(() => true);
      await riskService.start();
    });

    test("processes new tasks", async () => {
      let capturedResponse: any;
      serviceManagerMock.respondToTask.mockImplementation((...args: any[]) => {
        capturedResponse = args;
        return Promise.resolve(true);
      });

      // Simulate task event
      const eventHandler = serviceManagerMock.on.mock.calls[0][1];
      await eventHandler(1, testTask);

      // Wait for processing
      await new Promise((r) => setTimeout(r, 100));

      expect(capturedResponse).toBeDefined();
      expect(capturedResponse[1]).toBe(1); // taskId
    });

    test("calculates risk score within bounds", async () => {
      let capturedScore: number;
      serviceManagerMock.respondToTask.mockImplementation((_task: any, _id: any, score: number) => {
        capturedScore = score;
        return Promise.resolve(true);
      });

      const eventHandler = serviceManagerMock.on.mock.calls[0][1];
      await eventHandler(1, testTask);

      await new Promise((r) => setTimeout(r, 100));

      expect(typeof capturedScore).toBe("number");
      expect(capturedScore).toBeGreaterThanOrEqual(0);
      expect(capturedScore).toBeLessThanOrEqual(100);
    });
  });

  describe("Error Handling", () => {
    test("handles registration failure", async () => {
      registryMock.isOperator.mockImplementation(() => false);
      registryMock.registerOperator.mockImplementation(() => {
        throw new Error("Registration failed");
      });

      try {
        await riskService.start();
        expect(false).toBe(true); // Should not reach here
      } catch {
        expect(riskService.getState()).toBe("ERROR");
      }
    });

    test("handles task response failure", async () => {
      registryMock.isOperator.mockImplementation(() => true);
      await riskService.start();

      serviceManagerMock.respondToTask.mockImplementation(() => {
        throw new Error("Response failed");
      });

      const eventHandler = serviceManagerMock.on.mock.calls[0][1];
      await eventHandler(1, testTask);

      await new Promise((r) => setTimeout(r, 100));

      expect(riskService.getState()).toBe("ACTIVE");
    });
  });

  describe("Service Lifecycle", () => {
    test("stops properly", async () => {
      registryMock.isOperator.mockImplementation(() => true);
      await riskService.start();

      const listenerSpy = spyOn(serviceManagerMock, "removeAllListeners");
      await riskService.stop();

      expect(riskService.getState()).toBe("PAUSED");
      expect(listenerSpy).toHaveBeenCalled();
    });
  });
});
