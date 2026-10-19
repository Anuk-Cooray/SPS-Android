// scoring.ts
// Smart Parking (J26-IT-335) — Algorithmic Multi-Criteria Scoring & Dynamic Re-optimization Engine
// Mathematical formulation matching Dart ReoptimizationEngine (SYS-01, SYS-03)

export type VehicleSize = 'small' | 'medium' | 'large';
export type SlotType = 'normal' | 'disabled' | 'ev' | 'covered';
export type SlotState = 'available' | 'reserved' | 'held' | 'occupied' | 'blocked';

export interface ParkingSlotData {
  id: string;
  lotId?: string;
  row?: string;
  number?: number;
  size: VehicleSize;
  type: SlotType;
  walkingDistanceMeters: number;
  state: SlotState;
  bookingId?: string | null;
  updatedAt?: string | null;
  updatedBy?: string | null;
}

export interface ParkingLotData {
  id?: string;
  name?: string;
  totalSlots: number;
  freeSlots: number;
}

export interface VehicleData {
  size: VehicleSize;
  type?: string;
}

export interface UserPreferencesData {
  preferNearEntrance: boolean;
  coveredParkingOnly: boolean;
  allowUpgradeOffers?: boolean;
}

export interface ScoringWeights {
  distanceWeight: number; // w_dist (0.40)
  sizeFitWeight: number; // w_size (0.25)
  preferenceWeight: number; // w_pref (0.20)
  demandWeight: number; // w_demand (0.15)
  minImprovementMeters: number; // 50m
  minScoreImprovementPoints: number; // 20.0 points
  minScoreImprovementPercent?: number; // legacy alias
  upgradeTriggerEtaMinutes: number; // 10 min
  offerTimeoutSeconds: number; // 60s
}

export const DEFAULT_SCORING_WEIGHTS: ScoringWeights = {
  distanceWeight: 0.40,
  sizeFitWeight: 0.25,
  preferenceWeight: 0.20,
  demandWeight: 0.15,
  minImprovementMeters: 50,
  minScoreImprovementPoints: 20.0,
  minScoreImprovementPercent: 20.0,
  upgradeTriggerEtaMinutes: 10,
  offerTimeoutSeconds: 60,
};

export interface SlotScoreResult {
  slot: ParkingSlotData;
  totalScore: number;
  distanceScore: number;
  sizeFitScore: number;
  preferenceScore: number;
  demandPenalty: number;
  explanation: string;
  isEligible: boolean;
}

export interface UpgradeEvaluationResult {
  isUpgradeOffered: boolean;
  currentSlotScore: SlotScoreResult;
  candidateSlotScore?: SlotScoreResult;
  distanceSavedMeters?: number;
  scoreImprovementPoints?: number;
  scoreImprovementPercent?: number; // legacy alias
  decisionReason: string;
  evaluatedAt: Date;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

export function isSizeCompatible(slotSize: VehicleSize, vehicleSize: VehicleSize): boolean {
  if (vehicleSize === 'small') return true;
  if (vehicleSize === 'medium') {
    return slotSize === 'medium' || slotSize === 'large';
  }
  return slotSize === 'large';
}

/**
 * Scores a single parking slot according to multi-criteria algorithmic formulation (SYS-01).
 * Formula: S = 0.40 * S_dist + 0.25 * S_size + 0.20 * S_pref - 0.15 * P_demand
 */
export function scoreSlot(
  slot: ParkingSlotData,
  lot: ParkingLotData,
  vehicle: VehicleData,
  preferences: UserPreferencesData,
  weights: ScoringWeights = DEFAULT_SCORING_WEIGHTS
): SlotScoreResult {
  // 1. Vehicle Size Compatibility Check
  if (!isSizeCompatible(slot.size, vehicle.size)) {
    return {
      slot,
      totalScore: 0.0,
      distanceScore: 0.0,
      sizeFitScore: 0.0,
      preferenceScore: 0.0,
      demandPenalty: 0.0,
      explanation: `Slot size (${slot.size}) is too small for vehicle (${vehicle.size})`,
      isEligible: false,
    };
  }

  // 2. Normalized Distance Score (0 - 100)
  const maxWalkingMeters = 250.0;
  const distanceRatio = clamp(maxWalkingMeters - slot.walkingDistanceMeters, 0.0, maxWalkingMeters) / maxWalkingMeters;
  const distanceScore = distanceRatio * 100.0;

  // 3. Vehicle Size Fit Score (0 - 100)
  let sizeFitScore = 100.0;
  if (slot.size === vehicle.size) {
    sizeFitScore = 100.0;
  } else if (vehicle.size === 'small' && slot.size === 'large') {
    sizeFitScore = 60.0; // Wastage penalty
  } else if (vehicle.size === 'medium' && slot.size === 'large') {
    sizeFitScore = 80.0;
  } else if (vehicle.size === 'small' && slot.size === 'medium') {
    sizeFitScore = 85.0;
  }

  // 4. User Preference Score (0 - 100)
  // Non-distance categorical preferences (avoids double-counting with distanceScore)
  let preferenceScore = 50.0; // baseline neutral
  if (preferences.coveredParkingOnly) {
    if (slot.type === 'covered') {
      preferenceScore = 100.0;
    } else {
      preferenceScore = 10.0;
    }
  }
  preferenceScore = clamp(preferenceScore, 0.0, 100.0);

  // 5. Lot Demand Factor (0 - 100) — Slot-aware demand penalty
  const occupancyRate = lot.totalSlots > 0
    ? (lot.totalSlots - lot.freeSlots) / lot.totalSlots
    : 0.0;

  let turnoverMultiplier = 1.0;
  if (occupancyRate >= 0.70 && slot.walkingDistanceMeters <= 50) {
    turnoverMultiplier = 1.20; // High-turnover entrance zone during peak demand
  } else if (slot.walkingDistanceMeters > 150) {
    turnoverMultiplier = 0.80; // Deep perimeter zone
  }

  const demandPenalty = clamp(occupancyRate * 25.0 * turnoverMultiplier, 0.0, 100.0);

  // 6. Weighted Sum (SYS-01)
  const weightedTotal =
    weights.distanceWeight * distanceScore +
    weights.sizeFitWeight * sizeFitScore +
    weights.preferenceWeight * preferenceScore -
    weights.demandWeight * demandPenalty;

  const totalScore = clamp(weightedTotal, 0.0, 100.0);

  const explanation =
    `Walk: ${slot.walkingDistanceMeters}m · ` +
    `Size fit: ${slot.size} (${Math.round(sizeFitScore)}%) · ` +
    `Score: ${totalScore.toFixed(1)}`;

  return {
    slot,
    totalScore,
    distanceScore,
    sizeFitScore,
    preferenceScore,
    demandPenalty,
    explanation,
    isEligible: true,
  };
}

/**
 * Scores and ranks candidate slots in descending order of algorithm totalScore.
 */
export function scoreAndRankSlots(
  slots: ParkingSlotData[],
  lot: ParkingLotData,
  vehicle: VehicleData,
  preferences: UserPreferencesData,
  weights: ScoringWeights = DEFAULT_SCORING_WEIGHTS
): SlotScoreResult[] {
  const available = slots.filter((s) => s.state === 'available');
  const results = available
    .map((s) => scoreSlot(s, lot, vehicle, preferences, weights))
    .filter((r) => r.isEligible);

  results.sort((a, b) => b.totalScore - a.totalScore);
  return results;
}

/**
 * Evaluates dynamic in-transit slot re-optimization (SYS-03).
 */
export function evaluateInTransitUpgrade(
  currentSlot: ParkingSlotData,
  candidateSlots: ParkingSlotData[],
  lot: ParkingLotData,
  vehicle: VehicleData,
  preferences: UserPreferencesData,
  currentEtaMinutes: number,
  weights: ScoringWeights = DEFAULT_SCORING_WEIGHTS
): UpgradeEvaluationResult {
  const evaluatedAt = new Date();

  // Condition 1: Check driver preference
  if (preferences.allowUpgradeOffers === false) {
    return {
      isUpgradeOffered: false,
      currentSlotScore: scoreSlot(currentSlot, lot, vehicle, preferences, weights),
      decisionReason: 'Driver has disabled proactive upgrade offers in preferences.',
      evaluatedAt,
    };
  }

  // Condition 2: ETA check window
  if (currentEtaMinutes > weights.upgradeTriggerEtaMinutes) {
    return {
      isUpgradeOffered: false,
      currentSlotScore: scoreSlot(currentSlot, lot, vehicle, preferences, weights),
      decisionReason: `ETA (${currentEtaMinutes} min) is outside upgrade window (<= ${weights.upgradeTriggerEtaMinutes} min).`,
      evaluatedAt,
    };
  }

  const currentScore = scoreSlot(currentSlot, lot, vehicle, preferences, weights);

  const eligibleCandidates = candidateSlots
    .filter((s) => s.state === 'available' && s.id !== currentSlot.id)
    .map((s) => scoreSlot(s, lot, vehicle, preferences, weights))
    .filter((r) => r.isEligible);

  if (eligibleCandidates.length === 0) {
    return {
      isUpgradeOffered: false,
      currentSlotScore: currentScore,
      decisionReason: 'No alternative eligible slots available in parking facility.',
      evaluatedAt,
    };
  }

  eligibleCandidates.sort((a, b) => b.totalScore - a.totalScore);
  const bestCandidate = eligibleCandidates[0];

  const distanceSaved = currentSlot.walkingDistanceMeters - bestCandidate.slot.walkingDistanceMeters;
  const scoreDelta = bestCandidate.totalScore - currentScore.totalScore;
  const thresholdPoints = weights.minScoreImprovementPoints ?? weights.minScoreImprovementPercent ?? 20.0;

  const meetsDistance = distanceSaved >= weights.minImprovementMeters;
  const meetsScore = scoreDelta >= thresholdPoints;

  if (meetsDistance && meetsScore) {
    return {
      isUpgradeOffered: true,
      currentSlotScore: currentScore,
      candidateSlotScore: bestCandidate,
      distanceSavedMeters: distanceSaved,
      scoreImprovementPoints: scoreDelta,
      scoreImprovementPercent: scoreDelta,
      decisionReason: `Found superior slot ${bestCandidate.slot.id}: Saves ${distanceSaved}m walking (Score improved +${scoreDelta.toFixed(1)} points).`,
      evaluatedAt,
    };
  }

  return {
    isUpgradeOffered: false,
    currentSlotScore: currentScore,
    candidateSlotScore: bestCandidate,
    distanceSavedMeters: distanceSaved,
    scoreImprovementPoints: scoreDelta,
    scoreImprovementPercent: scoreDelta,
    decisionReason: `Best candidate ${bestCandidate.slot.id} did not exceed threshold (Saves ${distanceSaved}m / req: ${weights.minImprovementMeters}m, Score: +${scoreDelta.toFixed(1)} pts / req: ${thresholdPoints} pts).`,
    evaluatedAt,
  };
}
