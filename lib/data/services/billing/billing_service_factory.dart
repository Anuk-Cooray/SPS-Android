import '../service_contracts.dart';
import 'http_billing_service.dart';
import 'mock_billing_service.dart';

/// Switch only here. The default runs entirely offline.
const bool useBackend = false;

const backendBaseUrl = String.fromEnvironment(
  'BILLING_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/',
);

BillingService createBillingService() => useBackend
    ? HttpBillingService(baseUrl: backendBaseUrl)
    : MockBillingService();
