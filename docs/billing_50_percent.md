# Component 4: increment toward the 50% review

There is no supervisor checklist, so a numerical completion percentage cannot be
certified. This increment supplies three demonstrable acceptance criteria within
billing. Recommendations, occupancy detection and barrier hardware stay with their owners.

## Delivered behavior

- Issued quotes, invoices, payment attempts and callback deduplication survive API
  restart in local SQLite. A fresh HTTP client discovers an invoice by booking
  and keeps its original quote instead of silently repricing it.
- Missing sandbox keys yield a labelled mock checkout. The Android screen offers
  **Confirm mock**; this calls the DEBUG-only endpoint and then reads the
  invoice. Opening a checkout or returning from it never proves payment.
- Only paid invoices receive an exit QR. Backend passes are HMAC-SHA256 signed,
  valid for five minutes and stored durably. Repeated issuance returns the same
  unexpired pass. A replacement invalidates earlier passes; consumption succeeds
  once, including when two database connections compete. A consumed invoice
  cannot obtain another pass. Offline app passes say they cannot open a gate.

## Run and inspect locally

Terminal 1, from the repository root (reuse the installed temporary environment):

```sh
cd backend
DEBUG=true /private/tmp/sps-billing-venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The forecast artifact must already be trained. If missing, follow backend/README.md
for synthetic generation and training. Keep gateway keys blank for this demo.

Terminal 2, from the repository root:

```sh
export PATH="$PWD/.tools/flutter/bin:$PATH"
export PUB_CACHE=/private/tmp/sps-pub-cache
flutter devices
flutter run -d emulator-5554 --dart-define=BILLING_USE_BACKEND=true
```

If the emulator is absent, launch `flutter emulators --launch Pixel_8a_API_36`,
wait for Android's home screen, then check `flutter devices` again. The frontend
is the emulator window. The HTTP API is visible at http://127.0.0.1:8000/docs.
Default app mode without the define remains an offline simulation.

Open a checked-in booking → Pay and exit. A stay within ten minutes can settle
without payment, so use a longer stay to demonstrate a pending checkout. Tap Pay,
verify it remains pending, then Confirm mock. The paid receipt and QR
remain visible until Finish demo exit. That button completes the existing demo
booking callback; it does not consume the backend pass or open hardware.

Restart the backend using the same database path. Its invoices and pending mock
session tokens remain available. The HTTP billing service also recovers the invoice
when recreated. The team's booking state is still an app demo store: billing
persistence does not make other components' booking state survive app restart.

## Barrier handoff contract

`GET /api/v1/billing/invoices/{invoice_id}/exit-token` returns
`invoice_id`, `token`, UTC `expires_at`, and `is_mock=false` after settlement.
It returns 403 while unpaid, 404 for an unknown invoice and 409 after consumption.

The barrier backend may call `POST /api/v1/billing/exit-tokens/consume` with
`{"token":"scanned value"}` and `X-Barrier-Key`. Configure the matching
`BARRIER_INTEGRATION_KEY` only on trusted backends. The response contains
`accepted`, `invoice_id`, and `booking_id`. Replay is 409; expiry is 410;
invalid signatures are 400. A replacement pass makes an older one invalid.
This endpoint validates authorization only; no BarrierService or gate controller
has been implemented or modified. Consumption and physical opening need a
team-agreed recovery protocol before deployment.

## Remaining component work

External PayHere/Stripe sandbox checkout from the app and end-to-end provider
callbacks still need credentials and checkout client integration. Guard settlement
needs an authenticated team admin contract. Production work includes booking
ownership authentication, payment reconciliation/refunds, invoice amendments,
production database migrations/retention, signing-key rotation, and operational
recovery. Forecasts still use synthetic occupancy; real data evaluation and
calibrated uncertainty remain necessary. There is no parking-lot recommendation
implementation in this increment.
