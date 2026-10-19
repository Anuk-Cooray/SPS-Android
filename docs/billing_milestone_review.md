# Component 4: 15% milestone self-review

## Supervisor items

| Item | Delivered evidence |
|---|---|
| Directory / architecture | Typed models; extended BillingService with both old signatures retained; separate billing Provider; mock/HTTP factory; monochrome screen/widgets |
| Historical timestamp pipeline / baseline | Seeded 90-day data for three actual mock lot IDs; aware preprocessing; seven-day chronological holdout; optional Prophet / executed sklearn fallback; naive weekly comparison; saved metrics and plot |
| Fee engine / API / sandbox setup | Pure Decimal rule engine; 124 backend tests; versioned quote/invoice/status/payment/forecast routes; PayHere hash checks; Stripe test adapter; signed webhook tests; offline mock payment demo |

## Verification actually performed

- Flutter 3.47.7 / Dart 3.13.5 installed locally; dependencies resolved without
  changing pubspec dependencies or SDK constraints.
- flutter analyze: no issues. flutter test: all 36 passed, including baseline app
  smoke, billing state/models, local HTTP transport, shared pricing fixtures and
  screen/pending/guard/dark-chart cases.
- pytest: all 124 passed; one existing Starlette/httpx TestClient deprecation.
  Black, Ruff, dependency consistency and whitespace checks passed.
- Android emulator debug APK built, installed and launched. This verifies app
  startup; widget tests exercise the billing screen behaviors separately.
- Pipeline generate → train → reload → predict executed; synthetic model MAE
  0.0459–0.0491 and RMSE 0.0581–0.0650 across lots. Weekly baseline MAE
  0.0509–0.0534. These are synthetic results only; exact MAPE/counts/splits are
  in backend/ml/artifacts/metrics.json.
- Live Uvicorn health/docs/OpenAPI, forecasts, demand-aware quotes, retraining,
  and quote → invoice → mock callback → paid/duplicate-event flow succeeded.
  PayHere signatures and Stripe SDK-signed fixtures tested; no external sandbox
  checkout or actual credentials were used. Prophet fitting was not run.

## Clarifications / scope decisions

The booking's arrival extension fee is not parking overtime. The optional
arrivalExtensionFee/arrival_extension_fee input preserves that charge once,
without surge and inside the entry-day cap. Its client source is a demo placeholder
until authoritative booking storage exists. Upgrade metadata displays a zero
charge because no authoritative rate delta/history exists. The backend uses one
exit-hour forecast multiplier per quote; this tariff choice needs approval.

Only main.dart billing Provider/handoff wiring, billing model/service/UI/test
paths, backend and docs were changed, plus specifically requested ignore entries.
No teammate-owned state manager, admin dashboard, barrier or occupancy contract
was edited. The latest booking is passed into billing to avoid a pre-check-in
navigation snapshot. The SDK, data CSV, pickles, secrets and caches are ignored.

Commits are grouped by backend, Flutter integration and documentation under the
user's final instruction to make meaningful commits. The earlier no-commit
instruction was followed until that authorization. No co-author trailers are used.
The original per-step commit checklist is superseded by that grouping request.

## Remaining 85% / known gaps

- Team decision: MongoDB + Node.js/Firebase diagrams versus PostgreSQL + FastAPI.
- Supervisor sign-off on tariffs, arrival fees, caps and demand timing policy.
- Real CCTV data, data-quality monitoring, weather/event forecasts and calibrated
  uncertainty; later justified XGBoost/LSTM comparison, not a novelty claim now.
- Durable database and Redis/job coordination; invoice expiry/amendment, retry
  recovery, reconciliation/refunds and correct multiple-booking settlement.
- Actual provider test-client checkout in the frontend and external sandbox
  verification with credentials; live keys/payments remain out of scope.
- Authenticated guard-generated codes/confirmation and admin revenue, method mix,
  average-stay and forecast-vs-actual analytics (see billing_integration.md).
- Paid-only signed exit QR, expiration/single-use store and BarrierService
  verification. The displayed invoice QR never authorizes a physical barrier.
- Production auth/ownership, server-side booking charges, browser HTTP transport,
  release networking policy and hardware integration. These are not provided by
  the prototype. Offline and HTTP invoices are lost on process restart.
