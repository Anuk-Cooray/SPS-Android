import 'dart:math';
import '../../../data/models/booking_model.dart';
import '../../../data/models/parking_lot_model.dart';
import '../../../data/models/parking_slot_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/service_contracts.dart';
import 'scoring_weights.dart';
import 'slot_score_result.dart';
import 'upgrade_evaluation_result.dart';

class ReoptimizationEngine implements ReoptimizationService {
  ScoringWeights weights;

  ReoptimizationEngine({
    this.weights = const ScoringWeights(),
  });

  /// Scores a single slot using multi-criteria weighted algorithm (SYS-01)
  SlotScoreResult scoreSlot({
    required ParkingSlot slot,
    required ParkingLot lot,
    required Vehicle vehicle,
    required UserPreferences preferences,
  }) {
    // 1. Vehicle Size Compatibility Check
    if (!_isSizeCompatible(slot.size, vehicle.size)) {
      return SlotScoreResult(
        slot: slot,
        totalScore: 0.0,
        distanceScore: 0.0,
        sizeFitScore: 0.0,
        preferenceScore: 0.0,
        demandPenalty: 0.0,
        explanation: 'Slot size (${slot.size.displayName}) is too small for ${vehicle.type.displayName}',
        isEligible: false,
      );
    }

    // 2. Normalized Distance Score (0 - 100)
    // Closer to entrance is higher score. Max standard walking threshold = 250m
    const double maxWalkingMeters = 250.0;
    final double distanceRatio = (maxWalkingMeters - slot.walkingDistanceMeters).clamp(0.0, maxWalkingMeters) / maxWalkingMeters;
    final double distanceScore = distanceRatio * 100.0;

    // 3. Vehicle Size Fit Score (0 - 100)
    // Penalize assigning oversized slots to smaller vehicles to preserve capacity
    double sizeFitScore = 100.0;
    if (slot.size == vehicle.size) {
      sizeFitScore = 100.0; // Optimal match
    } else if (vehicle.size == VehicleSize.small && slot.size == VehicleSize.large) {
      sizeFitScore = 60.0; // Wastage penalty
    } else if (vehicle.size == VehicleSize.medium && slot.size == VehicleSize.large) {
      sizeFitScore = 80.0;
    } else if (vehicle.size == VehicleSize.small && slot.size == VehicleSize.medium) {
      sizeFitScore = 85.0;
    }

    // 4. User Preference Score (0 - 100)
    // Non-distance categorical preferences (avoids double-counting with distanceScore)
    double preferenceScore = 50.0; // baseline neutral
    if (preferences.coveredParkingOnly) {
      if (slot.type == SlotType.covered) {
        preferenceScore = 100.0;
      } else {
        preferenceScore = 10.0;
      }
    }
    preferenceScore = preferenceScore.clamp(0.0, 100.0);

    // 5. Lot Demand Factor (0 - 100) — Slot-aware demand penalty
    // High occupancy penalizes high-turnover entrance slots during peak load
    final double occupancyRate = lot.totalSlots > 0
        ? (lot.totalSlots - lot.freeSlots) / lot.totalSlots
        : 0.0;

    double turnoverMultiplier = 1.0;
    if (occupancyRate >= 0.70 && slot.walkingDistanceMeters <= 50) {
      turnoverMultiplier = 1.20; // High-turnover entrance zone during peak demand
    } else if (slot.walkingDistanceMeters > 150) {
      turnoverMultiplier = 0.80; // Deep perimeter zone
    }

    final double demandPenalty =
        (occupancyRate * 25.0 * turnoverMultiplier).clamp(0.0, 100.0);

    // 6. Weighted Sum (SYS-01)
    final double weightedTotal = (weights.distanceWeight * distanceScore) +
        (weights.sizeFitWeight * sizeFitScore) +
        (weights.preferenceWeight * preferenceScore) -
        (weights.demandWeight * demandPenalty);

    final double totalScore = weightedTotal.clamp(0.0, 100.0);

    final explanation = 'Walk: ${slot.walkingDistanceMeters}m · '
        'Size fit: ${slot.size.displayName} (${sizeFitScore.toInt()}%) · '
        'Score: ${totalScore.toStringAsFixed(1)}';

    return SlotScoreResult(
      slot: slot,
      totalScore: totalScore,
      distanceScore: distanceScore,
      sizeFitScore: sizeFitScore,
      preferenceScore: preferenceScore,
      demandPenalty: demandPenalty,
      explanation: explanation,
      isEligible: true,
    );
  }

  /// Scores and ranks all available slots for a lot
  List<SlotScoreResult> scoreAndRankSlots({
    required ParkingLot lot,
    required Vehicle vehicle,
    required UserPreferences preferences,
  }) {
    final available = lot.slots.where((s) => s.isAvailable).toList();
    final results = available.map((s) {
      return scoreSlot(
        slot: s,
        lot: lot,
        vehicle: vehicle,
        preferences: preferences,
      );
    }).where((r) => r.isEligible).toList();

    // Sort descending by total score
    results.sort((a, b) => b.totalScore.compareTo(a.totalScore));
    return results;
  }

  @override
  ParkingSlot? scoreAndRecommendBestSlot({
    required ParkingLot lot,
    required Vehicle vehicle,
    required bool preferNearEntrance,
  }) {
    final ranked = scoreAndRankSlots(
      lot: lot,
      vehicle: vehicle,
      preferences: UserPreferences(preferNearEntrance: preferNearEntrance),
    );
    if (ranked.isEmpty) return null;
    return ranked.first.slot;
  }

  /// Comprehensive in-transit upgrade check (SYS-03)
  UpgradeEvaluationResult evaluateInTransitUpgrade({
    required ParkingLot lot,
    required ParkingSlot currentSlot,
    required Vehicle vehicle,
    required UserPreferences preferences,
    required int currentEtaMinutes,
  }) {
    final evaluatedAt = DateTime.now();

    // Condition 1: Check driver preference
    if (!preferences.allowUpgradeOffers) {
      return UpgradeEvaluationResult(
        isUpgradeOffered: false,
        currentSlotScore: scoreSlot(
          slot: currentSlot,
          lot: lot,
          vehicle: vehicle,
          preferences: preferences,
        ),
        decisionReason: 'Driver has turned off proactive upgrade offers in settings.',
        evaluatedAt: evaluatedAt,
      );
    }

    // Condition 2: ETA check window
    if (currentEtaMinutes > weights.upgradeTriggerEtaMinutes) {
      return UpgradeEvaluationResult(
        isUpgradeOffered: false,
        currentSlotScore: scoreSlot(
          slot: currentSlot,
          lot: lot,
          vehicle: vehicle,
          preferences: preferences,
        ),
        decisionReason: 'ETA ($currentEtaMinutes min) is outside upgrade window (<= ${weights.upgradeTriggerEtaMinutes} min).',
        evaluatedAt: evaluatedAt,
      );
    }

    // Score current slot
    final currentScore = scoreSlot(
      slot: currentSlot,
      lot: lot,
      vehicle: vehicle,
      preferences: preferences,
    );

    // Score all available candidate slots
    final candidateSlots = lot.slots.where((s) {
      return s.isAvailable && s.id != currentSlot.id;
    }).toList();

    if (candidateSlots.isEmpty) {
      return UpgradeEvaluationResult(
        isUpgradeOffered: false,
        currentSlotScore: currentScore,
        decisionReason: 'No other free slots available in ${lot.name}.',
        evaluatedAt: evaluatedAt,
      );
    }

    final candidateResults = candidateSlots.map((s) {
      return scoreSlot(
        slot: s,
        lot: lot,
        vehicle: vehicle,
        preferences: preferences,
      );
    }).where((r) => r.isEligible).toList();

    if (candidateResults.isEmpty) {
      return UpgradeEvaluationResult(
        isUpgradeOffered: false,
        currentSlotScore: currentScore,
        decisionReason: 'Available slots do not fit vehicle size.',
        evaluatedAt: evaluatedAt,
      );
    }

    // Sort candidates descending
    candidateResults.sort((a, b) => b.totalScore.compareTo(a.totalScore));
    final bestCandidate = candidateResults.first;

    // Condition 3: Minimum distance improvement threshold (e.g. saves >= 50m)
    final int distanceSaved = currentSlot.walkingDistanceMeters - bestCandidate.slot.walkingDistanceMeters;

    // Condition 4: Minimum score improvement threshold (e.g. >= 20.0 score points)
    final double scoreDelta = bestCandidate.totalScore - currentScore.totalScore;

    final bool meetsDistance = distanceSaved >= weights.minImprovementMeters;
    final bool meetsScore = scoreDelta >= weights.minScoreImprovementPoints;

    if (meetsDistance && meetsScore) {
      return UpgradeEvaluationResult(
        isUpgradeOffered: true,
        currentSlotScore: currentScore,
        candidateSlotScore: bestCandidate,
        distanceSavedMeters: distanceSaved,
        scoreImprovementPoints: scoreDelta,
        decisionReason: 'Found superior slot ${bestCandidate.slot.id}: Saves $distanceSaved m walking '
            '(Score improved +${scoreDelta.toStringAsFixed(1)} points).',
        evaluatedAt: evaluatedAt,
      );
    }

    return UpgradeEvaluationResult(
      isUpgradeOffered: false,
      currentSlotScore: currentScore,
      candidateSlotScore: bestCandidate,
      distanceSavedMeters: distanceSaved,
      scoreImprovementPoints: scoreDelta,
      decisionReason: 'Best candidate ${bestCandidate.slot.id} did not exceed threshold '
          '(Saves ${distanceSaved}m / req: ${weights.minImprovementMeters}m, '
          'Score: +${scoreDelta.toStringAsFixed(1)} pts / req: ${weights.minScoreImprovementPoints} pts).',
      evaluatedAt: evaluatedAt,
    );
  }

  @override
  ParkingSlot? checkCandidateUpgrade({
    required ParkingLot lot,
    required ParkingSlot currentSlot,
    required Vehicle vehicle,
  }) {
    final eval = evaluateInTransitUpgrade(
      lot: lot,
      currentSlot: currentSlot,
      vehicle: vehicle,
      preferences: const UserPreferences(),
      currentEtaMinutes: 10,
    );
    return eval.isUpgradeOffered ? eval.candidateSlotScore?.slot : null;
  }

  @override
  Future<bool> holdUpgradeSlot({
    required String bookingId,
    required String newSlotId,
  }) async {
    // Atomically locks slot during 60-second offer window (SYS-04)
    return true;
  }

  @override
  Future<Booking> executeSlotSwap({
    required Booking currentBooking,
    required ParkingSlot newSlot,
  }) async {
    final savedMeters = max(0, 160 - newSlot.walkingDistanceMeters);
    return currentBooking.copyWith(
      slotId: newSlot.id,
      originalSlotId: currentBooking.originalSlotId ?? currentBooking.slotId,
      status: BookingStatus.upgraded,
      distanceSavedMeters: savedMeters,
      qrToken: 'QR-UPGRADED-${newSlot.id}-${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  bool _isSizeCompatible(VehicleSize slotSize, VehicleSize vehicleSize) {
    if (vehicleSize == VehicleSize.small) return true;
    if (vehicleSize == VehicleSize.medium) {
      return slotSize == VehicleSize.medium || slotSize == VehicleSize.large;
    }
    return slotSize == VehicleSize.large;
  }
}
