# HTTP billing adapter and service toggle

## Approach / alternatives
HttpBillingService uses Dart's built-in HttpClient for Android/desktop, so no new Flutter dependencies are needed. It serializes UTC ISO timestamps and integer LKR to the FastAPI paths, parses the common error envelope and exposes readable connection/timeout errors. It posts the unchanged returned quote when creating an invoice. Quote/invoice caches allow a pending invoice to resume within the same app process. Socket tests exercise the actual transport against a local HTTP server.

billing_service_factory.dart contains the single useBackend=false switch. Turning it on selects HTTP; the default base URL is http://10.0.2.2:8000 for Android emulator access to the host. BILLING_BASE_URL can be passed as a compile-time define for another device or HTTPS tunnel. The Provider wiring calls this factory and otherwise leaves parking navigation intact.

## Limitations
This dart:io adapter is for Android/desktop; backend mode on Flutter Web needs a browser transport. The screen starts sessions and refreshes invoices but does not embed PayHere form checkout or Stripe Elements/SDK confirmation. Sandbox credentials and actual checkout clients are separate backend setup. Missing-key backend mock sessions require a DEBUG callback; the app never silently confirms them. Release Android networking/cleartext policy remains outside the billing ownership scope; use an HTTPS endpoint for deployments. Restart recovery and durable invoice lookup by booking are future work.

## Three viva questions
- **Why 10.0.2.2?** It is the Android emulator's address for the host machine, where the demo API runs.
- **Why not re-create a quote on every retry?** A pending invoice must keep the same price as its checkout session.
- **Why no automatic paid result?** Only the fetched invoice status can confirm settlement.
