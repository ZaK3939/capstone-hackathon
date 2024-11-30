import { PoolMetrics } from "./types";

// Metric Weights
const WEIGHTS = {
  VOLUME: 0.25,
  TVL: 0.2,
  PRICE_IMPACT: 0.25,
  SWAP_COUNT: 0.15,
  FAILED_TX: 0.15,
} as const;

// Threshold Constants
const THRESHOLDS = {
  HIGH_VOLUME: 1_000_000, // $1M
  MIN_TVL: 100_000, // $100K
  MAX_PRICE_IMPACT: 0.05, // 5%
  HIGH_SWAP_COUNT: 1000, // per period
  HIGH_FAILURE_RATE: 0.05, // 5%
} as const;

export function calculateRiskScore(metrics: PoolMetrics): number {
  // Normalize and weight each metric
  const volumeScore = normalizeVolume(metrics.volumeUSD) * WEIGHTS.VOLUME;
  const tvlScore = normalizeTVL(metrics.tvlUSD) * WEIGHTS.TVL;
  const priceImpactScore = normalizePriceImpact(metrics.priceImpact) * WEIGHTS.PRICE_IMPACT;
  const swapScore = normalizeSwapCount(metrics.swapCount) * WEIGHTS.SWAP_COUNT;
  const failureScore = normalizeFailureRate(metrics.failedTxCount / metrics.swapCount) * WEIGHTS.FAILED_TX;

  // Combine scores
  const totalScore = volumeScore + tvlScore + priceImpactScore + swapScore + failureScore;

  // Scale to 0-100
  return Math.round(totalScore * 100);
}

// Normalization Functions
function normalizeVolume(volume: number): number {
  return Math.min(volume / THRESHOLDS.HIGH_VOLUME, 1);
}

function normalizeTVL(tvl: number): number {
  return Math.max(1 - tvl / THRESHOLDS.MIN_TVL, 0);
}

function normalizePriceImpact(impact: number): number {
  return Math.min(impact / THRESHOLDS.MAX_PRICE_IMPACT, 1);
}

function normalizeSwapCount(count: number): number {
  return Math.min(count / THRESHOLDS.HIGH_SWAP_COUNT, 1);
}

function normalizeFailureRate(rate: number): number {
  return Math.min(rate / THRESHOLDS.HIGH_FAILURE_RATE, 1);
}

// Anomaly Detection
export function detectAnomalies(metrics: PoolMetrics): string[] {
  const anomalies: string[] = [];

  if (metrics.volumeUSD > THRESHOLDS.HIGH_VOLUME) {
    anomalies.push("HIGH_VOLUME");
  }
  if (metrics.tvlUSD < THRESHOLDS.MIN_TVL) {
    anomalies.push("LOW_TVL");
  }
  if (metrics.priceImpact > THRESHOLDS.MAX_PRICE_IMPACT) {
    anomalies.push("HIGH_PRICE_IMPACT");
  }
  if (metrics.swapCount > THRESHOLDS.HIGH_SWAP_COUNT) {
    anomalies.push("HIGH_SWAP_COUNT");
  }
  if (metrics.failedTxCount / metrics.swapCount > THRESHOLDS.HIGH_FAILURE_RATE) {
    anomalies.push("HIGH_FAILURE_RATE");
  }

  return anomalies;
}
