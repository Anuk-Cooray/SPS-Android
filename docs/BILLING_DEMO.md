# Billing milestone: local frontend and supervisor demo

## Open the frontend

The frontend is the Flutter Android app. It does not require the Python server in
default mock mode. Flutter is installed at:

`/Users/minolirathnayake/Desktop/SPS-Android/.tools/flutter`

From the repository root:

```sh
export PATH="$PWD/.tools/flutter/bin:$PATH"
export PUB_CACHE=/private/tmp/sps-pub-cache
flutter pub get
flutter emulators
flutter emulators --launch Pixel_8a_API_36
flutter devices
flutter run -d emulator-5554
```

Use the actual Android device ID printed by flutter devices. The emulator launch
opens its visible window. Alternatively open Android Studio → Device Manager and
press Play for Pixel_8a_API_36, then run flutter run with its device ID. In Android
Studio's Flutter settings, select the SDK folder above. Open the repository root
as the Flutter project; MainActivity.kt alone is the Android host, not the UI.

`flutter run` opens the app in the emulator. Press r in that terminal for hot reload,
R for hot restart and q to stop. A browser is not needed. The SDK is ignored by
Git and the shell exports apply only to the current terminal.

## Five-minute supervisor demo

1. **0:00–1:00 — App architecture.** Show BillingService, its separate Provider
   state, immutable models and the single useBackend=false service toggle.
2. **1:00–2:00 — Frontend.** Open the active booking, follow navigation → Show QR
   → check in/confirm parked → Pay and exit. The booking must have checkedInAt.
   Show actual duration, monochrome breakdown, recorded arrival fee/upgrade and
   synthetic demand chart. An immediate exit may cost zero due to grace.
3. **2:00–3:00 — Payment semantics.** Choose Pay at booth (guard): it stays unpaid
   and shows an invoice-reference QR. Choose a sandbox digital option for the
   offline simulation. Explain that invoice confirmation, not a fake timer, ends
   the booking and that barrier hardware is not integrated.
4. **3:00–4:00 — Backend.** Start it below, open /docs and show quote/invoice/status
   routes. Run demo_mock_payment.py for the separate offline API payment workflow.
5. **4:00–5:00 — Forecast and evidence.** Show metrics.json and forecast_demo.png,
   the chronological holdout/baseline comparison, passing tests and the remaining
   integration decisions. State clearly that all occupancy data is synthetic.

The app mock and API mock are separate demo stores. The API mock requires its
DEBUG callback; the app's default offline service simulates digital confirmation.
No real saved Visa card or external payment charge is used.

## Run the backend (optional for the default frontend)

From the repository root, if the temporary environment needs recreation:

```sh
python3 -m venv /private/tmp/sps-billing-venv
/private/tmp/sps-billing-venv/bin/pip install -r backend/requirements.txt
cd backend
/private/tmp/sps-billing-venv/bin/python -m ml.generate_synthetic_data
MPLCONFIGDIR=/private/tmp/sps-matplotlib /private/tmp/sps-billing-venv/bin/python -m ml.train_baseline
DEBUG=true /private/tmp/sps-billing-venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Open http://127.0.0.1:8000/docs on the computer. In another terminal from backend/:

```sh
/private/tmp/sps-billing-venv/bin/python demo_mock_payment.py
```

Keys can remain blank. For HTTP frontend mode, set useBackend=true in
lib/data/services/billing/billing_service_factory.dart and rebuild. Android
emulator calls the computer at http://10.0.2.2:8000. Physical devices need a
reachable host address or HTTPS tunnel via BILLING_BASE_URL. See backend/README.md
for sandbox credentials, callbacks and currency configuration. The screen does
not embed real provider checkout clients; start/refresh and mock mode are the
milestone integration. Close an old app/server session before starting another;
invoice storage is process-local and lost on restart.

## Verification commands

From the repository root with the exports above:

```sh
flutter analyze --no-pub
flutter test --no-pub
/private/tmp/sps-billing-venv/bin/pytest -q backend
/private/tmp/sps-billing-venv/bin/ruff check backend
/private/tmp/sps-billing-venv/bin/black --check backend
```

Latest verified: 36 Flutter tests, 124 backend tests, clean Flutter analysis and
Black/Ruff. Android debug APK built and launched on Pixel API 36. The backend
suite has one existing Starlette/httpx deprecation warning. Optional Prophet and
external sandbox transactions were not run; scikit-learn fallback and signed
webhook fixtures were tested.
