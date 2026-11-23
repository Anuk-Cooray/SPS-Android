// analytics_service.dart
// Smart Parking (J26-IT-335) — Production Analytics & Event Tracking Abstraction

import 'package:flutter/foundation.dart';

class AnalyticsService {
  static final AnalyticsService instance = AnalyticsService._internal();

  AnalyticsService._internal();

  /// Logs a business or system lifecycle event
  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
  }) async {
    if (kDebugMode) {
      debugPrint('[AnalyticsService] Event: $name | Params: $parameters');
    }
    // Safe hook for Firebase Analytics in production
  }

  /// Logs screen/route view transition
  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    if (kDebugMode) {
      debugPrint('[AnalyticsService] Screen View: $screenName ($screenClass)');
    }
  }

  /// Sets persistent user property or ID
  Future<void> setUserId(String? id) async {
    if (kDebugMode) {
      debugPrint('[AnalyticsService] User ID: $id');
    }
  }
}
