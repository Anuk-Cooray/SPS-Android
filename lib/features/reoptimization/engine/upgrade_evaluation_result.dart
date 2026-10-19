import 'slot_score_result.dart';

class UpgradeEvaluationResult {
  final bool isUpgradeOffered;
  final SlotScoreResult currentSlotScore;
  final SlotScoreResult? candidateSlotScore;
  final int distanceSavedMeters;
  final double scoreImprovementPoints;
  final String decisionReason;
  final DateTime evaluatedAt;

  const UpgradeEvaluationResult({
    required this.isUpgradeOffered,
    required this.currentSlotScore,
    this.candidateSlotScore,
    this.distanceSavedMeters = 0,
    this.scoreImprovementPoints = 0.0,
    required this.decisionReason,
    required this.evaluatedAt,
  });

  @Deprecated('Use scoreImprovementPoints instead')
  double get scoreImprovementPercent => scoreImprovementPoints;

  Map<String, dynamic> toTelemetryMap() => {
        'timestamp': evaluatedAt.toIso8601String(),
        'isUpgradeOffered': isUpgradeOffered,
        'currentSlot': currentSlotScore.slot.id,
        'currentScore': currentSlotScore.totalScore.toStringAsFixed(2),
        'candidateSlot': candidateSlotScore?.slot.id ?? 'none',
        'candidateScore': candidateSlotScore?.totalScore.toStringAsFixed(2) ?? '0.00',
        'distanceSavedMeters': distanceSavedMeters,
        'scoreImprovementPoints': scoreImprovementPoints.toStringAsFixed(1),
        'scoreImprovementPercent': scoreImprovementPoints.toStringAsFixed(1),
        'decisionReason': decisionReason,
      };
}
