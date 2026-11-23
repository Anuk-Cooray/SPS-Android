class ScoringWeights {
  final double distanceWeight; // w_dist (default 0.40)
  final double sizeFitWeight; // w_size (default 0.25)
  final double preferenceWeight; // w_pref (default 0.20)
  final double demandWeight; // w_demand (default 0.15)

  final int minImprovementMeters; // minimum walking distance saved (e.g. 50m)
  final double minScoreImprovementPoints; // minimum score delta (e.g. 20.0 points)
  final int upgradeTriggerEtaMinutes; // trigger when ETA <= 10 min
  final int offerTimeoutSeconds; // hold window (default 60s)
  final String version; // e.g. "v1.0.0"

  const ScoringWeights({
    this.distanceWeight = 0.40,
    this.sizeFitWeight = 0.25,
    this.preferenceWeight = 0.20,
    this.demandWeight = 0.15,
    this.minImprovementMeters = 50,
    double? minScoreImprovementPoints,
    @Deprecated('Use minScoreImprovementPoints instead')
    double? minScoreImprovementPercent,
    this.upgradeTriggerEtaMinutes = 10,
    this.offerTimeoutSeconds = 60,
    this.version = 'v1.0.0',
  }) : minScoreImprovementPoints = minScoreImprovementPoints ?? minScoreImprovementPercent ?? 20.0;

  /// True if the 4 objective weights sum to 1.0 within ±0.001 tolerance
  bool get isValidSum =>
      ((distanceWeight + sizeFitWeight + preferenceWeight + demandWeight) - 1.0).abs() <= 0.001;

  double get weightSum =>
      distanceWeight + sizeFitWeight + preferenceWeight + demandWeight;

  @Deprecated('Use minScoreImprovementPoints instead')
  double get minScoreImprovementPercent => minScoreImprovementPoints;

  ScoringWeights copyWith({
    double? distanceWeight,
    double? sizeFitWeight,
    double? preferenceWeight,
    double? demandWeight,
    int? minImprovementMeters,
    double? minScoreImprovementPoints,
    @Deprecated('Use minScoreImprovementPoints instead')
    double? minScoreImprovementPercent,
    int? upgradeTriggerEtaMinutes,
    int? offerTimeoutSeconds,
    String? version,
  }) {
    return ScoringWeights(
      distanceWeight: distanceWeight ?? this.distanceWeight,
      sizeFitWeight: sizeFitWeight ?? this.sizeFitWeight,
      preferenceWeight: preferenceWeight ?? this.preferenceWeight,
      demandWeight: demandWeight ?? this.demandWeight,
      minImprovementMeters: minImprovementMeters ?? this.minImprovementMeters,
      minScoreImprovementPoints: minScoreImprovementPoints ??
          minScoreImprovementPercent ??
          this.minScoreImprovementPoints,
      upgradeTriggerEtaMinutes:
          upgradeTriggerEtaMinutes ?? this.upgradeTriggerEtaMinutes,
      offerTimeoutSeconds: offerTimeoutSeconds ?? this.offerTimeoutSeconds,
      version: version ?? this.version,
    );
  }

  Map<String, dynamic> toJson() => {
        'distanceWeight': distanceWeight,
        'sizeFitWeight': sizeFitWeight,
        'preferenceWeight': preferenceWeight,
        'demandWeight': demandWeight,
        'minImprovementMeters': minImprovementMeters,
        'minScoreImprovementPoints': minScoreImprovementPoints,
        'minScoreImprovementPercent': minScoreImprovementPoints,
        'upgradeTriggerEtaMinutes': upgradeTriggerEtaMinutes,
        'offerTimeoutSeconds': offerTimeoutSeconds,
        'version': version,
      };

  factory ScoringWeights.fromJson(Map<String, dynamic> json) => ScoringWeights(
        distanceWeight: (json['distanceWeight'] as num?)?.toDouble() ?? 0.40,
        sizeFitWeight: (json['sizeFitWeight'] as num?)?.toDouble() ?? 0.25,
        preferenceWeight:
            (json['preferenceWeight'] as num?)?.toDouble() ?? 0.20,
        demandWeight: (json['demandWeight'] as num?)?.toDouble() ?? 0.15,
        minImprovementMeters:
            (json['minImprovementMeters'] as num?)?.toInt() ?? 50,
        minScoreImprovementPoints:
            (json['minScoreImprovementPoints'] as num?)?.toDouble() ??
                (json['minScoreImprovementPercent'] as num?)?.toDouble() ??
                20.0,
        upgradeTriggerEtaMinutes:
            (json['upgradeTriggerEtaMinutes'] as num?)?.toInt() ?? 10,
        offerTimeoutSeconds:
            (json['offerTimeoutSeconds'] as num?)?.toInt() ?? 60,
        version: json['version'] as String? ?? 'v1.0.0',
      );
}
