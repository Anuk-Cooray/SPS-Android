// feasibility.ts
// Smart Parking (J26-IT-335) — Learned Sri Lankan ETA Residual Correction Serving
// Serves learned linear regression model against research baseline and provider estimates

import * as etaModel from './models/eta_model_v1.json';

export interface ArrivalFeasibilityInput {
  originLat: number;
  originLng: number;
  destLat: number;
  destLng: number;
  requestedArrivalTime: Date;
  congestionMultiplier?: number;
  providerDurationMinutes?: number;
  originZone?: string;
  weatherFlag?: number;
  holidayFlag?: number;
}

export interface ArrivalFeasibilityOutput {
  isFeasible: boolean;
  requestedTime: Date;
  earliestFeasibleTime: Date;
  recommendedArrivalTime: Date;
  drivingDurationMinutes: number;
  drivingDistanceKm: number;
  lateByMinutes: number;
  predictedEtaMinBaseline: number;
  predictedEtaMinProvider: number;
  predictedEtaMinCorrected: number;
  residualCorrectionFactor: number;
  modelVersion: string;
}

/**
 * Validates travel duration from driver origin to target parking facility.
 * Computes:
 *   1. Heuristic Research Baseline (22 km/h city average, 1.35x curvature)
 *   2. Provider Estimate (commercial Routes API)
 *   3. Learned Sri Lankan ETA Residual Correction Model (v1.0.0-linear)
 */
export function evaluateArrivalFeasibility(input: ArrivalFeasibilityInput): ArrivalFeasibilityOutput {
  const dX = (input.destLng - input.originLng) * 110.574 * 0.9927;
  const dY = (input.destLat - input.originLat) * 110.574;
  const distSq = dX * dX + dY * dY;
  const straightDistKm = distSq > 0 ? Math.sqrt(distSq) : 0.2;
  const drivingDistanceKm = Number((straightDistKm * 1.35).toFixed(1));

  // 1. Research Baseline Heuristic (Straight-line x 1.35 curvature, 22 km/h average)
  const congestionMultiplier = input.congestionMultiplier ?? 1.15;
  const baseDurationMinutes = (drivingDistanceKm / 22.0) * 60.0;
  const baselineDurationMinutes = Math.max(3, Math.round(baseDurationMinutes * congestionMultiplier));

  // 2. Provider API duration
  const providerMinutes = input.providerDurationMinutes ??
    Math.max(3, Math.round((drivingDistanceKm / 36.0) * 60.0 * 1.10));

  // 3. Learned Residual Correction Model (eta_model_v1.json)
  const now = new Date();
  const hour = input.requestedArrivalTime.getHours();
  const dayOfWeek = input.requestedArrivalTime.getDay() === 0 ? 7 : input.requestedArrivalTime.getDay();
  const isWeekend = dayOfWeek >= 6 ? 1.0 : 0.0;

  const timeDecimal = hour + input.requestedArrivalTime.getMinutes() / 60.0;
  const isPeak =
    !isWeekend &&
    !input.holidayFlag &&
    ((timeDecimal >= 7.5 && timeDecimal <= 9.75) || (timeDecimal >= 16.5 && timeDecimal <= 19.5))
      ? 1.0
      : 0.0;

  const sinHour = Math.sin((2 * Math.PI * hour) / 24.0);
  const cosHour = Math.cos((2 * Math.PI * hour) / 24.0);

  const zone = input.originZone ?? 'zone_Malabe_Kaduwela';
  const weatherFlag = input.weatherFlag ?? 0.0;
  const holidayFlag = input.holidayFlag ?? 0.0;

  // Dot product with model coefficients
  const coefficients = (etaModel.coefficients as Record<string, number>) ?? {};
  let factor = etaModel.intercept ?? 1.10461;

  factor += (coefficients['distanceKm'] ?? 0.0) * drivingDistanceKm;
  factor += (coefficients['isPeakHour'] ?? 0.0) * isPeak;
  factor += (coefficients['isWeekend'] ?? 0.0) * isWeekend;
  factor += (coefficients['weatherFlag'] ?? 0.0) * weatherFlag;
  factor += (coefficients['holidayFlag'] ?? 0.0) * holidayFlag;
  factor += (coefficients['sin_hour'] ?? 0.0) * sinHour;
  factor += (coefficients['cos_hour'] ?? 0.0) * cosHour;

  // Zone specific indicator
  const zoneKey = zone.startsWith('zone_') ? zone : `zone_${zone}`;
  if (coefficients[zoneKey] !== undefined) {
    factor += coefficients[zoneKey];
  }

  // Clamped residual ratio
  const clampedFactor = Math.min(Math.max(factor, 0.5), 3.0);
  const correctedDurationMinutes = Math.max(3, Math.round(providerMinutes * clampedFactor));

  // Earliest feasible arrival time based on corrected ETA
  const earliestFeasibleTime = new Date(now.getTime() + correctedDurationMinutes * 60 * 1000);
  const differenceMs = input.requestedArrivalTime.getTime() - earliestFeasibleTime.getTime();
  const isFeasible = differenceMs >= 0;
  const lateByMinutes = isFeasible ? 0 : Math.round(Math.abs(differenceMs) / (60 * 1000));

  let recommendedArrivalTime: Date;
  if (isFeasible) {
    recommendedArrivalTime = input.requestedArrivalTime;
  } else {
    // Round up to nearest 5 minutes
    const remainder = earliestFeasibleTime.getMinutes() % 5;
    const addedMinutes = remainder === 0 ? 0 : 5 - remainder;
    recommendedArrivalTime = new Date(earliestFeasibleTime.getTime() + addedMinutes * 60 * 1000);
    recommendedArrivalTime.setSeconds(0, 0);
  }

  return {
    isFeasible,
    requestedTime: input.requestedArrivalTime,
    earliestFeasibleTime,
    recommendedArrivalTime,
    drivingDurationMinutes: correctedDurationMinutes,
    drivingDistanceKm,
    lateByMinutes,
    predictedEtaMinBaseline: baselineDurationMinutes,
    predictedEtaMinProvider: providerMinutes,
    predictedEtaMinCorrected: correctedDurationMinutes,
    residualCorrectionFactor: Number(clampedFactor.toFixed(3)),
    modelVersion: etaModel.modelVersion ?? 'v1.0.0-linear',
  };
}
