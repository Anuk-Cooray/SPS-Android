// app_config.dart
// Smart Parking (J26-IT-335) — Central Environment & Research Configuration

/// Central configuration managing demo simulation controls and production environment settings.
class AppConfig {
  /// Compile-time constant from environment. Defaults to true for evaluation & defense demos.
  static const bool _kDemoModeFromEnv = bool.fromEnvironment('DEMO_MODE', defaultValue: true);

  /// Target deployment environment ('dev' or 'prod'), configurable via --dart-define=ENVIRONMENT=prod
  static const String environment = String.fromEnvironment('ENVIRONMENT', defaultValue: 'dev');

  static bool get isProduction => environment == 'prod';
  static bool get isDevelopment => environment == 'dev';

  static bool? _demoModeOverride;

  /// When true, enables examiner simulation controls (route scrubber, fast-forward
  /// hold countdown chips, test upgrade/late arrival triggers, preset demo credentials).
  /// When false, runs strictly in production mode connecting to live Firestore telemetry and real timers.
  static bool get kDemoMode => _demoModeOverride ?? (_kDemoModeFromEnv && !isProduction);

  /// Allows automated unit tests or examiner settings to toggle demo mode dynamically.
  static set demoModeOverride(bool? value) {
    _demoModeOverride = value;
  }

  /// Resets runtime override back to environment default.
  static void resetOverride() {
    _demoModeOverride = null;
  }
}
