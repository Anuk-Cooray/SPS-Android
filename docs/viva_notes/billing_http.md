# HTTP billing adapter and service toggle

## Approach / alternatives
HttpBillingService uses Dart's built-in HttpClient for Android/desktop, so no new Flutter dependencies are needed. It serializes UTC ISO timestamps and integer LKR to the FastAPI paths, parses the common error envelope and exposes readable connection/timeout errors. It posts the unchanged returned quote when creating an invoice. A booking invoice lookup recovers its fixed quote even with a new app cache. Socket tests exercise the actual transport against a local HTTP server.

billing_service_factory.dart reads BILLING_USE_BACKEND (default false). Passing --dart-define=BILLING_USE_BACKEND=true selects HTTP; the default base URL is http://10.0.2.2:8000 for Android emulator access to the host. BILLING_BASE_URL can be passed as a compile-time define for another device or HTTPS tunnel. The Provider wiring calls this factory and otherwise leaves parking navigation intact.

## Limitations
This dart:io adapter is for Android/desktop; backend mode on Flutter Web needs a browser transport. The screen starts sessions and refreshes invoices but does not embed PayHere form checkout or Stripe Elements/SDK confirmation. Sandbox credentials and actual checkout clients are separate backend setup. Missing-key backend mock sessions expose an explicit Confirm mock action calling the DEBUG endpoint; the app never silently confirms them. Release Android networking/cleartext policy remains outside the billing ownership scope; use an HTTPS endpoint for deployments. Paid-only exit passes are fetched separately after invoice settlement.

## Three viva questions
- **Why 10.0.2.2?** It is the Android emulator's address for the host machine, where the demo API runs.
- **Why not re-create a quote on every retry?** A pending invoice must keep the same price as its checkout session.
- **Why no automatic paid result?** Only the fetched invoice status can confirm settlement.
