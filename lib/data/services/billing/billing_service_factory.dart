import '../service_contracts.dart';
import 'http_billing_service.dart';
import 'mock_billing_service.dart';

/// Opt in with --dart-define=BILLING_USE_BACKEND=true; default is offline.
const bool useBackend = bool.fromEnvironment('BILLING_USE_BACKEND');

const backendBaseUrl = String.fromEnvironment(
  'BILLING_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/',
);

BillingService createBillingService() => useBackend
    ? HttpBillingService(baseUrl: backendBaseUrl)
    : MockBillingService();
