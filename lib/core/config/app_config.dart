// app_config.dart
// Smart Parking (J26-IT-335) — Central Environment & Research Configuration

/// Central configuration managing demo simulation controls and production environment settings.
class AppConfig {
  /// Compile-time constant from environment. Defaults to true for evaluation & defense demos.
  static const bool _kDemoModeFromEnv = bool.fromEnvironment('DEMO_MODE', defaultValue: true);

  /// Target deployment environment ('dev' or 'prod'), configurable via --dart-define=ENVIRONMENT=prod
  static const String environment = String.fromEnvironment('ENVIRONMENT', defaultValue: 'dev');

  /// Routes Auth, Firestore and Cloud Functions to the local Firebase Emulator Suite
  /// (--dart-define=USE_EMULATORS=true). Never honoured in production builds.
  static const bool _kUseEmulatorsFromEnv = bool.fromEnvironment('USE_EMULATORS', defaultValue: false);

  /// Emulator host (--dart-define=EMULATOR_HOST=...). 127.0.0.1 is mapped to 10.0.2.2 on Android.
  static const String emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '127.0.0.1');

  static bool get useEmulators => _kUseEmulatorsFromEnv && !isProduction;

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
