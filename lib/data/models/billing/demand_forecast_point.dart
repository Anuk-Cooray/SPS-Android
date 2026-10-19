/// Occupancy fractions, rather than monetary values.
class DemandForecastPoint {
  final DateTime ts;
  final double yhat;
  final double yhatLower;
  final double yhatUpper;
  final double demandLevel;

  DemandForecastPoint({
    required DateTime ts,
    required this.yhat,
    required this.yhatLower,
    required this.yhatUpper,
    required this.demandLevel,
  }) : ts = ts.toUtc();

  factory DemandForecastPoint.fromJson(Map<String, dynamic> json) =>
      DemandForecastPoint(
        ts: DateTime.parse(json['ts'] as String),
        yhat: (json['yhat'] as num).toDouble(),
        yhatLower: (json['yhat_lower'] as num).toDouble(),
        yhatUpper: (json['yhat_upper'] as num).toDouble(),
        demandLevel: (json['demand_level'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
    'ts': ts.toIso8601String(),
    'yhat': yhat,
    'yhat_lower': yhatLower,
    'yhat_upper': yhatUpper,
    'demand_level': demandLevel,
  };
}
