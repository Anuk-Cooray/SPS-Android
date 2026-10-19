# Component 4 billing milestone backend

Steps 3–6 provide a pure pricing engine, a synthetic-data baseline pipeline, and
FastAPI quote/forecast endpoints, in-memory invoices and sandbox payment adapters.
No credentials are needed for the current API; generate/train the model before
requesting forecasts or quotes that omit demand.

From the repository root:

```sh
python3 -m venv /private/tmp/sps-billing-venv
/private/tmp/sps-billing-venv/bin/pip install -r backend/requirements.txt
cd backend
/private/tmp/sps-billing-venv/bin/pytest
/private/tmp/sps-billing-venv/bin/uvicorn app.main:app --reload
```

Open http://127.0.0.1:8000/docs, or GET `/api/v1/health`.
POST `/api/v1/billing/quote` using the example in the interactive docs. Money is
whole LKR. Requests require timezone-aware ISO timestamps; response times are UTC.
Pricing uses Asia/Colombo calendar days.

## Assumptions requiring supervisor/team confirmation

- Rates mirror Flutter lots: main 100, new P2 80, sports 50 LKR/hour.
- A stay up to 10 minutes is free. For longer stays, all minutes count; grace is
  not subtracted. Each calendar day's duration rounds up to 15-minute blocks.
- Weekday peak windows are 07:30–09:30 and 15:30–17:30, with a 1.25 multiplier
  only on actual overlapping minutes. Rounded padding attracts normal rate.
- `extension_minutes` is the trailing overtime portion already included between
  entry and exit. Its extra 0.5 premium brings that portion to 1.5 times base
  rate. It must not exceed the recorded stay. The Step 7 Dart mock now uses the same trailing-overtime interpretation;
  shared fixtures check both implementations.
- Booking.extensionFee represents an arrival-deadline fee, not overtime.
  Step 7 forwards it as optional integer arrival_extension_fee. Add it once
  without surge, inside the entry-day cap; parking grace does not erase it.
  The demo trusts the existing client booking value; production must load it
  from authoritative server booking storage. Never infer overtime minutes.
- Peak and overtime premiums add independently when they overlap. Upgrade rate
  delta applies only to actual remaining minutes. The pure engine accepts the
  delta/duration, but the public route cannot infer them from slot IDs and uses
  zero until an authoritative slot-rate source exists. Do not trust client rates.
- Demand surge is 1 below 0.6, linear to 1.5 at 0.9 and capped at 1.5. It applies
  to all charges before the 1,200 LKR cap per Colombo day.
- Per-day monetary rounding uses Decimal ROUND_HALF_UP. `subtotal` sums rounded
  base and premium items; `surge_amount` includes surge, cap discounts and the
  rounding adjustment, so it can be negative. Items always sum to total.
- Omitted demand uses the synthetic forecast at the exit hour, with one demand
  multiplier for the whole quote. Missing/unusable models return HTTP 503 rather
  than assuming no demand. Quotes remain provisional; the offline Flutter UI is
  not wired here yet.
- Keep FastAPI; MongoDB + Node.js/Firebase versus PostgreSQL + FastAPI remains a
  team decision. No database, auth, barrier hardware or live payments yet.

## Five-minute supervisor demo (current increment)

1. Show `/docs` and the typed quote example.
2. Submit one off-peak hour: 100 LKR at the main lot.
3. Change demand to 0.9: 150 LKR. Explain the rule-based calculation.
4. Demonstrate a partial peak and a daily cap using the engine tests.
5. Show passing tests and explain why payment/forecast integration is still pending.

## Remaining 85%

Real occupancy from Samudi's LotOccupancyService; baseline forecast integration;
sandbox checkout/webhooks; guard confirmation with Anuk's dashboard; revenue and
payment analytics; exit QR verification with Varunprasath's BarrierService;
authentication, durable database and Redis; later XGBoost/LSTM comparison only if
justified. No deep learning is part of this milestone.

## Step 4: synthetic forecast pipeline

Run from `backend/` with the virtual environment above:

```sh
/private/tmp/sps-billing-venv/bin/python -m ml.generate_synthetic_data
MPLCONFIGDIR=/private/tmp/sps-matplotlib /private/tmp/sps-billing-venv/bin/python -m ml.train_baseline
/private/tmp/sps-billing-venv/bin/python -m ml.predict --lot-id lot-main --horizon-hours 24 --output ml/artifacts/forecast_demo.json
```

The default generator seed is 335. It produces 90 days × 24 hours × three lots
(6,480 rows), starting 2026-07-01 in Colombo time. IDs/capacities come directly
from Flutter mock_data.dart. These are **synthetic**, not campus observations.
The module header defines every column. Weekends, class-time peaks, a simulated
semester-break dip, rain and events affect occupancy; arrivals are illustrative
and do not form a balanced vehicle-entry/exit ledger.

`pipeline.py` rejects naive timestamps and invalid values, keeps the last exact
duplicate per lot, sorts, and resamples hourly within each lot. Missing occupancy,
capacity, rain and event values carry forward from the past; missing arrivals
are zero. `was_imputed` identifies filled hours. The training demo refuses imputed
targets during evaluation rather than treating guesses as ground truth. There is
no backward interpolation across the training/test boundary. Features use Colombo
hour/day/weekend/peak plus rain/event; stored timestamps remain UTC. Prophet's
`ds` is converted to naive Colombo wall time only at its library boundary.

Training defaults to Prophet with daily/weekly seasonality and rain regressor
when installed. Prophet is optional: `pip install prophet` in the virtual environment
if desired. Without it, automatic fallback is scikit-learn's seeded
GradientBoostingRegressor (100 depth-3 trees). `--model gradient_boosting` makes
that selection explicit; `--model prophet` fails clearly if unavailable. Fitting
errors are surfaced rather than silently switching algorithms.

Each lot reserves the final 168 hours as a test set. Training never uses these
targets. Test predictions use zero future rain/event inputs, matching the CLI's
current unknown-weather assumption. Compare against occupancy at exactly the same
hour seven days earlier (all baseline source hours are in the training set).
Metrics are MAE/RMSE in occupancy fractions and MAPE percent, excluding true zero
occupancy with the nonzero count reported. MAPE is unstable near zero; MAE/RMSE
are the primary comparisons. No claim that the model must beat the baseline.

After evaluation, a separate fit on all history produces the demo model. Outputs:

- `ml/artifacts/metrics.json`: held-out per-lot metrics and split timestamps.
- `ml/artifacts/baseline.pkl`: local fitted models, ignored by Git; regenerate.
- `ml/artifacts/forecast_demo.png`: three monochrome 24-hour forecasts for slides.
- `ml/artifacts/forecast_demo.json`: optional CLI sample for one lot.

The shaded band is the 90th-percentile absolute **training** residual around the
prediction, clipped to [0,1]. It is illustrative, optimistic and **not calibrated
90% future coverage**. Both band and `demand_level` are occupancy fractions; money
never uses these floating-point values directly. Prediction clamps occupancy to
[0,1]. The CLI starts immediately after the synthetic history by default, not
at today's date. `--start 2026-10-20T00:00:00+05:30` allows a different aware start;
extrapolating a synthetic historical model to today is not real demand evidence.

Read only locally generated pickle files. Synthetic CSVs and pickles are ignored;
metrics and the labelled plot can be reviewed and committed later by the student.
The Step 5 API lazily caches the local model on its first forecast request.
Later, replace the synthetic source
with CCTV-derived occupancy from Samudi's `LotOccupancyService`, add actual weather
forecasts/event schedules, assess missing-data quality and recalibrate intervals.
The innovation is demand-aware pricing feeding billing; using Prophet or boosting
alone is not research novelty. No trained network or external pretrained weights.

### Recorded Step 4 validation

Executed with the automatic scikit-learn fallback (Prophet not installed). Python 3.13; 61 backend tests passed, with one existing Starlette/httpx TestClient deprecation warning. Black, Ruff and diff whitespace checks passed. The plot was opened and visually inspected. Prophet fitting itself has not been run.

| Lot | Model MAE | Weekly MAE | Model RMSE | Weekly RMSE | Model MAPE % | Weekly MAPE % |
|---|---:|---:|---:|---:|---:|---:|
| lot-main | 0.0467 | 0.0526 | 0.0607 | 0.0680 | 26.92 | 38.11 |
| lot-new-p2 | 0.0459 | 0.0534 | 0.0581 | 0.0679 | 24.52 | 31.85 |
| lot-sports | 0.0491 | 0.0509 | 0.0650 | 0.0694 | 22.56 | 29.02 |

Each lot has 1,992 training hours and 168 test hours. These results describe only the seeded synthetic dataset, not real campus accuracy. See artifacts/metrics.json for exact timestamps and zero-target exclusions.

## Step 5: forecast API and demand-aware quotes

Generate/train with the Step 4 commands first. Then, from `backend/`:

```sh
/private/tmp/sps-billing-venv/bin/uvicorn app.main:app --reload
curl 'http://127.0.0.1:8000/api/v1/forecast/demand?lot_id=lot-main&horizon_hours=24'
curl -X POST http://127.0.0.1:8000/api/v1/billing/quote \
  -H 'Content-Type: application/json' \
  -d '{"booking_id":"BK-FORECAST","lot_id":"lot-main","entry_time":"2026-10-19T07:00:00+05:30","exit_time":"2026-10-19T08:00:00+05:30"}'
```

`GET /api/v1/forecast/demand` returns the existing Flutter contract's list of
`ts, yhat, yhat_lower, yhat_upper, demand_level`. Default horizon is 24; permitted
range is 1–168 hours. The first point is the **next Colombo hourly boundary after
now**, unlike the CLI demo's first hour after historical data. For example, at
08:45 Colombo, the first point is 09:00 Colombo / 03:30 UTC. Times serialize in
UTC; values are occupancy fractions. OpenAPI labels the endpoint synthetic.

`ForecastService` lazily loads one locally trained bundle into memory per API
process. Repeated lots and quotes reuse it. A lock serializes prediction and
retraining in that process. It does not train on startup or silently generate
missing data. Missing, corrupt or incompatible models return the normal error
envelope with HTTP 503 / `FORECAST_UNAVAILABLE`, including regeneration guidance.
An explicit `demand_level` still permits pricing-engine demos without the model.
This override is for the unauthenticated milestone demo; production must make the
server's demand authoritative rather than letting drivers choose it.

**Pricing assumption:** when demand is omitted, select the forecast for the
Colombo hour containing `exit_time`. One such demand multiplier applies to the
whole quote, including multi-hour/multi-day stays; per-minute peak overlap is
still calculated independently by the engine. The explanation records the
synthetic demand and source hour. Do not describe this as a historical actual
occupancy measurement. Demand is converted via `Decimal(str(level))` before
entering the money engine. This exit-hour tariff policy needs supervisor sign-off;
hourly demand integration is a possible later enhancement.

To enable the development-only retraining endpoint, stop the server and run:

```sh
DEBUG=true MPLCONFIGDIR=/private/tmp/sps-matplotlib /private/tmp/sps-billing-venv/bin/uvicorn app.main:app --reload
curl -X POST http://127.0.0.1:8000/api/v1/forecast/retrain
```

DEBUG defaults to false; retraining then returns 403 / `DEBUG_REQUIRED`. The
flag is read from the process environment or backend/.env (environment variables
take precedence). Retraining is synchronous and uses the
existing synthetic CSV. It trains/evaluates in a temporary artifact directory,
validates candidate predictions, then replaces the model/metrics/plot and updates
the cache. A failed fit leaves the prior model usable. Restart other API workers
manually after retraining: no distributed cache invalidation or job queue exists.
The earlier optional CLI forecast JSON is a separate saved sample; retraining
updates the model, metrics and PNG, not that JSON. Keep this unauthenticated dev
operation on a local development server. No production retraining API yet.

The saved history ends in September 2026. Current-time API responses extrapolate
those synthetic weekday/time patterns; there is no freshness guarantee, live
weather, real CCTV data or calibrated uncertainty. The same synthetic limitations
apply when these predictions feed a quote.

Step 5 validation: **77 backend tests passed**, with the same existing TestClient
deprecation warning. Black and Ruff passed. Live Uvicorn checks returned 24
forecast points, a 113 LKR partial-peak quote using omitted-demand forecasting,
a successful three-lot DEBUG retrain and a valid post-retrain forecast; `/docs`
and OpenAPI returned HTTP 200. No production payment behavior is implemented; Step 6 adds sandbox/mock settlement.

## Step 6: sandbox payments and offline settlement

Copy `.env.example` to `backend/.env`; leave all keys blank for the offline demo.
Never commit `.env`. Run **one API worker**: invoices, issued quotes, sessions and
webhook deduplication are held in memory and lost on reload/restart. PostgreSQL
versus MongoDB remains the team's decision; `InvoiceRepository` is the boundary.
No authentication or ownership checks exist in this local milestone API.

```sh
# Terminal 1, from backend/ (DEBUG permits only the local mock confirmation):
DEBUG=true /private/tmp/sps-billing-venv/bin/uvicorn app.main:app
# Terminal 2, from backend/:
/private/tmp/sps-billing-venv/bin/python demo_mock_payment.py
```

The demo uses explicit demand, so it runs without the forecast artifact. It shows
quote → pending invoice → pending mock session → mock callback → paid invoice,
then repeats the callback to demonstrate deduplication. It never contacts a live
gateway. The default mock fallback does **not** itself mark an invoice paid.

API flow:

1. POST `/api/v1/billing/quote` and keep its response unchanged.
2. POST `/api/v1/billing/invoices` with `booking_id` and that `quote` object.
   Client-forged quotes are rejected; an identical retry reuses the invoice.
   One invoice per booking is supported; price amendments after invoicing return
   409 and need a later amendment/cancellation workflow. Quotes currently have
   no expiry, so this is a provenance check, not a production tariff lock.
3. POST `/api/v1/billing/invoices/{id}/pay` with `method` payhere/stripe/guard.
   Repeat requests reuse a pending checkout. Switching a pending digital method
   returns 409; an awaiting-guard invoice can switch to digital.
4. Poll GET `/api/v1/billing/invoices/{id}`. Only verified matching settlement
   changes a nonzero invoice to paid. A zero-fee invoice settles without charging.
5. Provider callbacks verify their signature and must match the stored session's
   provider, payment ID, amount and currency. Duplicate events do not charge or
   settle twice; a late failure never downgrades a paid invoice.

`PaymentSession` includes provider, is_mock, status, integer amount_minor and
currency, plus provider-specific checkout_fields/client_secret. Minor units are
integer cents; invoice amounts remain integer whole LKR. These extra fields are
for the later HTTP Flutter integration; the existing screen remains unchanged.
Do not log or publish client_secret or mock confirmation tokens.

**Mock:** missing PayHere keys or incomplete Stripe credentials select `provider:
mock`, `is_mock: true`, with a prominent message. POST `/billing/webhooks/mock`
requires DEBUG=true and the session's mock_webhook_token, invoice_id, session_id,
amount_minor, currency and paid/failed status (see demo script). It can confirm
only mock sessions. It is a local simulation facility, never a real verification
bypass. Real provider routes reject mock callbacks. Configured provider failures
return an error rather than silently succeeding or switching to mock mode.

**Guard:** method guard returns awaiting_guard and leaves the invoice unpaid.
Guard confirmation, booth invoice/code generation and authenticated admin
operations are TODOs for integration with Anuk's dashboard. No teammate-owned
screen was edited. Returning from checkout does not prove payment; the
`payment-return` endpoint only tells the user to refresh their invoice.

### PayHere sandbox setup

Create a PayHere sandbox merchant account. In its Integrations area, register the
public domain/app and obtain the sandbox Merchant ID and domain-specific Merchant
Secret. Set PAYHERE_MERCHANT_ID, PAYHERE_MERCHANT_SECRET and PUBLIC_BASE_URL in
`.env`, then restart Uvicorn. No credentials were supplied or used in development.

PayHere checkout fields target only `https://sandbox.payhere.lk/pay/checkout` and
must be submitted as an **HTML form POST**, not a GET URL. The server creates the
hash; the merchant secret is never returned. Request hash uses upper-case MD5
of merchant ID + order ID + amount with two decimal places + currency + upper-case
MD5 of secret. Notify verification additionally includes the status code after
currency and hashes the original amount text. The order ID is the payment session
ID, which binds the notification to the stored invoice/amount. Status 2 is paid,
0 remains pending, and -1/-2 fail the attempt. Chargebacks/refunds are not handled
by this milestone ledger and require later reconciliation.

The request/notification formulas, sandbox URL, form encoding and confirmation
semantics were checked against the current developer documentation during this
session. Fixed local test vectors are unit tests, not official merchant examples.
Fictional Sandbox Student contact fields are supplied for this demo; replace them
with the proper test-customer profile before account testing. A Flutter gateway
SDK or hosted checkout form remains future client integration.

A callback needs a public HTTPS URL. Examples (install the tunnel separately):

```sh
ngrok http 8000
# or
cloudflared tunnel --url http://localhost:8000
```

Use the resulting HTTPS origin as PUBLIC_BASE_URL. PayHere's notify URL becomes
`<origin>/api/v1/billing/webhooks/payhere`. Register the appropriate public domain
and secret in the sandbox account; a changing tunnel URL may require updating
that registration. POST notifications are form-encoded; browser return/cancel
URLs never mark invoices paid.

### Stripe test setup and currency fallback

Use a Stripe sandbox/test workspace and get its **sk_test_** API key; live keys
are rejected. Configure an event endpoint for payment_intent.succeeded,
payment_intent.payment_failed and payment_intent.canceled, and copy that endpoint's
whsec_ signing secret into STRIPE_WEBHOOK_SECRET. For local forwarding:

```sh
stripe listen --forward-to localhost:8000/api/v1/billing/webhooks/stripe
```

Use the CLI's printed signing secret for that forwarded endpoint. The backend
creates a test PaymentIntent and returns its client_secret; complete it with a
Stripe test client/Elements or a test-only confirmation tool. No raw card details
are handled by this backend. Webhooks use the exact raw body and Stripe SDK
signature/timestamp verification; live-mode events are rejected. An unrelated
signed event is acknowledged without changing an invoice. Generic `stripe trigger`
events lack this invoice/session metadata and cannot settle an arbitrary invoice.

LKR is the default. If the test account rejects currency, provide an explicit
team-approved STRIPE_USD_PER_LKR decimal to enable a USD retry on a currency
parameter rejection. Alternatively set STRIPE_CURRENCY=usd with that rate to
select the test fallback directly. No exchange rate is guessed or fetched; this
is a configured demo conversion, not financial exchange-rate guidance. USD minor
units use Decimal ROUND_HALF_UP; the invoice stays LKR and the session records
its expected USD amount/currency for matching. Account currency support and
minimum-charge rules still apply; a small converted invoice may be below Stripe's
minimum. Other API errors surface as 502, rather than silently retrying in USD.

Validation uses simulated PayHere notifications, SDK-verified signed Stripe
fixtures and a stubbed Stripe create call. **No external sandbox transaction or
real credentials have been tested.** Persistent reconciliation, refunds,
chargebacks, recovery after a provider timeout, distributed locking and guard
confirmation remain later work. PaymentIntent idempotency covers a recorded
checkout attempt; crash/unknown-outcome recovery needs durable attempt storage.

Step 6 validation: **116 backend tests passed**, with the existing Starlette/httpx
TestClient deprecation warning. Black, Ruff, dependency consistency and whitespace
checks passed. The running Uvicorn offline demo completed a 100 LKR quote through
paid mock settlement, confirmed duplicate-callback handling and served the payment
OpenAPI/docs. Stripe fixture signature verification used the installed SDK;
PaymentIntent creation was stubbed. No external sandbox transaction was run.

## Step 7: Flutter billing integration

Flutter 3.47.7 / Dart 3.13.5 is installed locally at `.tools/flutter` (ignored by
Git). The project SDK requirement and Flutter dependencies were left unchanged.
Commands from the repository root:

```sh
PUB_CACHE=/private/tmp/sps-pub-cache .tools/flutter/bin/flutter pub get
PUB_CACHE=/private/tmp/sps-pub-cache .tools/flutter/bin/flutter analyze --no-pub
PUB_CACHE=/private/tmp/sps-pub-cache .tools/flutter/bin/flutter test --no-pub
PUB_CACHE=/private/tmp/sps-pub-cache .tools/flutter/bin/flutter run
```

The default is the offline mock. Follow the app's booking/check-in flow, then
open Pay and exit. Check-in time and booked arrival fees are read from the latest
booking, rather than the navigation callback's earlier snapshot. Quotes use
actual elapsed time; a missing check-in prevents payment. Digital methods are
labelled sandbox and simulate confirmation in the offline service. Booth payment
stays awaiting_guard with an invoice-reference QR, not an exit authorization.
The chart shows synthetic demand and an illustrative band in monochrome.

For HTTP mode, change only `const bool useBackend = false` to true in
`lib/data/services/billing/billing_service_factory.dart`, start the trained backend,
and rebuild the app. Android emulator host URL defaults to `http://10.0.2.2:8000/`.
For another device or an HTTPS tunnel, set the compile-time URL explicitly:

```sh
PUB_CACHE=/private/tmp/sps-pub-cache .tools/flutter/bin/flutter run --dart-define=BILLING_BASE_URL=https://your-demo-tunnel.example/
```

The HTTP adapter uses Dart's built-in HttpClient and is intended for Android/
desktop; Flutter Web backend mode needs a browser transport. It sends UTC times,
parking overtime minutes and the separate recorded `arrival_extension_fee`.
That fee is added once without surge, within the entry-day cap; grace affects
parking only. The demo client supplies this existing booking value. A production
server must load it from an authoritative booking store. The shared tariff fixture
file `test/billing/pricing_cases.json` is checked by both Python and Dart tests.
The offline mock now mirrors the backend's tariff using integer fractions, while
its demand pattern remains a simple mock rather than the trained Python model.

**Payment behavior in HTTP mode:** a session remains pending until its backend
invoice is confirmed. The screen offers Check status and never treats a checkout
URL, QR or redirect as paid. PayHere form submission and Stripe SDK/Elements
confirmation are not embedded in this milestone screen; complete those sandbox
sessions using the configured provider test client, then refresh. For missing-key
backend mock sessions, use the DEBUG-only callback with that session's token and
invoice ID. Starting the same invoice/method again through `/pay` returns the
existing session, including its mock callback fields. Do not use the standalone
demo script to confirm a different screen invoice: it creates a fresh booking.

Within the current app process, HTTP state resumes an already created invoice
instead of repricing it while checkout is pending. Neither app nor backend invoice
identity persists across restart; recovery and invoice amendments remain future
work. No real card, exit token or barrier operation is provided. Android release
network permissions/HTTP policy and iOS transport exceptions are outside the
billing ownership scope; use HTTPS for deployments. No platform manifest was
edited in this step.
