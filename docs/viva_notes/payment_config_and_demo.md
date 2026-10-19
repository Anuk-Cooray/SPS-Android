# Payment configuration and offline demo

## What it does / why
PaymentSettings reads backend/.env with process environment taking precedence. Sensitive fields are excluded from its dataclass representation. The cached service keeps settings stable until server restart. DEBUG is explicitly false by default and gates retraining/mock callbacks. Invalid configured conversion rates fail clearly. Blank credentials permit the local mock demo without gateway access. `.env.example` contains no real keys.

`demo_mock_payment.py` calls a running local API using explicit demand (no model artifact needed), creates a fresh demo booking/quote/invoice, starts a mock checkout, confirms through its development callback, then checks paid status and duplicate-event handling. It prints only invoice ID, total and result flags. A non-mock provider is rejected by this demo client. Real sandbox adapters remain available separately with test credentials.

## Alternatives / limitations
This is a development setup, not a production secret manager or authenticated payment UI. Environment keys must be test/sandbox only; Stripe live keys are rejected. Run one API process because invoice state and mock tokens are in memory. Do not publish session secrets or use the DEBUG mock endpoint as a real payment bypass. The Flutter payment screen is still scheduled for Step 7.

## Three viva questions
- **Why an example environment file?** Students can configure local credentials without placing secrets in source control.
- **Why explicit demand in the payment demo?** It isolates payment state transitions from model availability while the forecast API has separate tests.
- **What does the demo prove?** The local quote/invoice/session/callback workflow works; it does not prove an external sandbox transaction completed.
