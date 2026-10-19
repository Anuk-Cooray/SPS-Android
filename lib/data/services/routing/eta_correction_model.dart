// eta_correction_model.dart
// Smart Parking (J26-IT-335) — Learned Sri Lankan ETA Residual Correction Inference Engine
// Evaluates linear regression weights on commercial routing estimates to correct localized Colombo delays

import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';

class EtaCorrectionModel {
  static const String currentVersion = 'v1.0.0-linear';

  final String version;
  final double intercept;
  final Map<String, double> coefficients;

  const EtaCorrectionModel({
    this.version = currentVersion,
    this.intercept = 1.10461,
    this.coefficients = const {
      'distanceKm': 0.00528,
      'isPeakHour': 0.40159,
      'isWeekend': -0.11233,
      'weatherFlag': 0.2842,
      'holidayFlag': -0.17506,
      'sin_hour': 0.00139,
      'cos_hour': -0.00265,
      'zone_Colombo-01_Fort': -0.02145,
      'zone_Colombo-03_Kollupitiya': 0.01153,
      'zone_Kandy_Road_Kelaniya': 0.01952,
      'zone_Malabe_Kaduwela': 0.02843,
      'zone_Nugegoda_Maharagama': -0.03804,
    },
  });

  /// Factory loading the serialized model JSON from Flutter rootBundle assets.
  static Future<EtaCorrectionModel> loadFromAsset({
    String assetPath = 'assets/models/eta_model_v1.json',
  }) async {
    try {
      final jsonStr = await rootBundle.loadString(assetPath);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final coefRaw = data['coefficients'] as Map<String, dynamic>? ?? {};
      final parsedCoef = coefRaw.map((k, v) => MapEntry(k, (v as num).toDouble()));

      return EtaCorrectionModel(
        version: data['modelVersion'] as String? ?? currentVersion,
        intercept: (data['intercept'] as num?)?.toDouble() ?? 1.10461,
        coefficients: parsedCoef,
      );
    } catch (_) {
      // Fallback to static embedded coefficients if asset loading fails
      return const EtaCorrectionModel();
    }
  }

  /// Calculates the predicted residual correction ratio r = actual / provider.
  double predictResidualRatio({
    required double distanceKm,
    required DateTime departureTime,
    String? originZone,
    bool isRain = false,
    bool isHoliday = false,
  }) {
    final hour = departureTime.hour;
    final minute = departureTime.minute;
    final timeDecimal = hour + (minute / 60.0);

    final dayOfWeek = departureTime.weekday; // 1=Mon .. 7=Sun
    final isWeekend = (dayOfWeek == 6 || dayOfWeek == 7) ? 1.0 : 0.0;

    final isMorningRush = timeDecimal >= 7.5 && timeDecimal <= 9.75;
    final isEveningRush = timeDecimal >= 16.5 && timeDecimal <= 19.5;
    final isPeakHour = (isWeekend == 0.0 && !isHoliday && (isMorningRush || isEveningRush)) ? 1.0 : 0.0;

    final hourRad = 2.0 * pi * hour / 24.0;
    final sinHour = sin(hourRad);
    final cosHour = cos(hourRad);

    double factor = intercept;
    factor += (coefficients['distanceKm'] ?? 0.0) * distanceKm;
    factor += (coefficients['isPeakHour'] ?? 0.0) * isPeakHour;
    factor += (coefficients['isWeekend'] ?? 0.0) * isWeekend;
    factor += (coefficients['weatherFlag'] ?? 0.0) * (isRain ? 1.0 : 0.0);
    factor += (coefficients['holidayFlag'] ?? 0.0) * (isHoliday ? 1.0 : 0.0);
    factor += (coefficients['sin_hour'] ?? 0.0) * sinHour;
    factor += (coefficients['cos_hour'] ?? 0.0) * cosHour;

    if (originZone != null) {
      final zoneKey = originZone.startsWith('zone_') ? originZone : 'zone_$originZone';
      if (coefficients.containsKey(zoneKey)) {
        factor += coefficients[zoneKey]!;
      }
    }

    // Clamp residual factor to realistic boundaries [0.5, 3.0]
    return factor.clamp(0.5, 3.0);
  }

  /// Computes the corrected driving duration in minutes from raw provider duration.
  int computeCorrectedMinutes({
    required int providerDurationMinutes,
    required double distanceKm,
    required DateTime departureTime,
    String? originZone,
    bool isRain = false,
    bool isHoliday = false,
  }) {
    final ratio = predictResidualRatio(
      distanceKm: distanceKm,
      departureTime: departureTime,
      originZone: originZone,
      isRain: isRain,
      isHoliday: isHoliday,
    );

    final corrected = (providerDurationMinutes * ratio).round();
    return max(3, corrected);
  }
}
