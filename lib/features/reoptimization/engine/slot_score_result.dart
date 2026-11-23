import '../../../data/models/parking_slot_model.dart';

class SlotScoreResult {
  final ParkingSlot slot;
  final double totalScore; // 0 - 100
  final double distanceScore; // 0 - 100
  final double sizeFitScore; // 0 - 100
  final double preferenceScore; // 0 - 100
  final double demandPenalty; // 0 - 100
  final String explanation;
  final bool isEligible;

  const SlotScoreResult({
    required this.slot,
    required this.totalScore,
    required this.distanceScore,
    required this.sizeFitScore,
    required this.preferenceScore,
    required this.demandPenalty,
    required this.explanation,
    this.isEligible = true,
  });

  Map<String, dynamic> toTelemetryMap() => {
        'slotId': slot.id,
        'walkingDistanceMeters': slot.walkingDistanceMeters,
        'totalScore': totalScore.toStringAsFixed(2),
        'distanceScore': distanceScore.toStringAsFixed(2),
        'sizeFitScore': sizeFitScore.toStringAsFixed(2),
        'preferenceScore': preferenceScore.toStringAsFixed(2),
        'demandPenalty': demandPenalty.toStringAsFixed(2),
        'explanation': explanation,
      };
}
