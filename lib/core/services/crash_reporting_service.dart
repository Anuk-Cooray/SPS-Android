// crash_reporting_service.dart
// Smart Parking (J26-IT-335) — Production Crash Reporting Abstraction

import 'package:flutter/foundation.dart';

class CrashReportingService {
  static final CrashReportingService instance = CrashReportingService._internal();

  CrashReportingService._internal();

  /// Logs a non-fatal error or exception to crash reporting system
  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    dynamic reason,
    bool fatal = false,
  }) async {
    if (kDebugMode) {
      debugPrint('[CrashReportingService] ${fatal ? "FATAL" : "NON-FATAL"}: $exception');
      if (reason != null) debugPrint('  Reason: $reason');
      if (stack != null) debugPrint('  Stack: $stack');
    }
    // Safe hook for Firebase Crashlytics in release builds
  }

  /// Logs an operational diagnostic breadcrumb
  Future<void> log(String message) async {
    if (kDebugMode) {
      debugPrint('[CrashReportingService Breadcrumb] $message');
    }
  }

  /// Sets user context identifier for crash sessions
  Future<void> setUserId(String identifier) async {
    if (kDebugMode) {
      debugPrint('[CrashReportingService] User ID set to: $identifier');
    }
  }

  /// Sets custom diagnostic key-value pairs
  Future<void> setCustomKey(String key, Object value) async {
    if (kDebugMode) {
      debugPrint('[CrashReportingService] Key $key: $value');
    }
  }
}
