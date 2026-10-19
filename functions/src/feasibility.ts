// feasibility.ts
// Smart Parking (J26-IT-335) — Algorithmic Travel Duration & Feasibility Validation (SYS-01, SYS-03)

export interface ArrivalFeasibilityInput {
  originLat: number;
  originLng: number;
  destLat: number;
  destLng: number;
  requestedArrivalTime: Date;
  congestionMultiplier?: number;
}

export interface ArrivalFeasibilityOutput {
  isFeasible: boolean;
  requestedTime: Date;
  earliestFeasibleTime: Date;
  recommendedArrivalTime: Date;
  drivingDurationMinutes: number;
  drivingDistanceKm: number;
  lateByMinutes: number;
}

/**
 * Validates travel duration from driver origin to target parking facility.
 * Enforces Colombo arterial traffic model (22 km/h city average, 1.35x curvature factor).
 */
export function evaluateArrivalFeasibility(input: ArrivalFeasibilityInput): ArrivalFeasibilityOutput {
  const dX = (input.destLng - input.originLng) * 110.574 * 0.9927;
  const dY = (input.destLat - input.originLat) * 110.574;
  const distSq = dX * dX + dY * dY;
  const straightDistKm = distSq > 0 ? Math.sqrt(distSq) : 0.2;
  const drivingDistanceKm = Number((straightDistKm * 1.35).toFixed(1));

  const congestionMultiplier = input.congestionMultiplier ?? 1.15;
  const baseDurationMinutes = (drivingDistanceKm / 22.0) * 60.0;
  const trafficDurationMinutes = Math.round(baseDurationMinutes * congestionMultiplier);
  const effectiveDurationMinutes = Math.max(3, trafficDurationMinutes);

  const now = new Date();
  const earliestFeasibleTime = new Date(now.getTime() + effectiveDurationMinutes * 60 * 1000);

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
    drivingDurationMinutes: effectiveDurationMinutes,
    drivingDistanceKm,
    lateByMinutes,
  };
}
