# Smart Parking System (SPS)
**SLIIT Research Project J26-IT-335**

A mobile application for intelligent parking lot management, featuring dynamic slot re-optimization, vision-based occupancy monitoring, automated QR barrier access, and digital billing.

---

## Team Components & Architecture

This repository is organized using a **Feature-First Architecture** so team members can work in parallel on their respective modules:

| Component | Lead | Directory | Contract Interface |
|---|---|---|---|
| **Dynamic Slot Re-optimization & Reservation** | **Anuk Cooray (Team Lead)** | `lib/features/reoptimization/` | `ReoptimizationService` |
| **CCTV Occupancy Detection** | **Samudi** | `lib/features/home_map/` | `LotOccupancyService` |
| **QR Barrier & Find My Car** | **Varunprasath** | `lib/features/barrier_checkin/` | `BarrierService` |
| **Smart Billing & QR Payment** | **Rathnayake** | `lib/features/billing/` | `BillingService` |

---

## Directory Structure

```
lib/
├── core/
│   ├── theme/          # AppTheme, monochrome + blue accent (#2563EB), Manrope typography
│   ├── widgets/        # Shared buttons, map painters, inputs
│   └── utils/
├── data/
│   ├── models/         # User, Vehicle, ParkingLot, ParkingSlot, Booking, ParkingEvent
│   └── services/       # Service contracts, mock data seeds, and central state manager
└── features/
    ├── auth/           # M1: Login, OTP verification & vehicle onboarding
    ├── home_map/       # M2/M3: Campus map explorer & nearby lot sheets
    ├── reoptimization/ # M4-M8: Slot scoring, navigation, dynamic upgrade offers, late auto-cancel
    ├── barrier_checkin/# M9-M10: QR generation, gate barrier trigger, Find My Car
    ├── billing/        # M11: Billing calculation, invoice breakdown, digital payment
    ├── profile/        # M14: Multi-vehicle manager & driver preferences
    └── admin/          # A1-A5: Live lot occupancy & research telemetry dashboard
```

---

## Getting Started

### Prerequisites
* Flutter SDK 3.47+ (Dart 3.13+)
* Android SDK (API 34+)

### Installation
```bash
git clone https://github.com/Anuk-Cooray/SPS-Android.git
cd SPS-Android
flutter pub get
flutter run
```

---

---

## Run Locally (Firebase Emulator Suite & Server Authority)

The reservation authority in this system runs strictly on the server using **Firebase Cloud Functions (Node 20 / TypeScript)** and **Cloud Firestore atomic transactions** to guarantee race condition immunity and autonomous 15-minute hold auto-release even if mobile devices are disconnected or killed.

### Quick start (free, no Blaze plan needed)
Everything runs on your machine: Auth, Firestore and Cloud Functions in the emulators, and the dev app on an Android emulator. The login code is shown in the app instead of being emailed.

```powershell
# Terminal 1: start the emulators (Ctrl+C to stop; data is saved to .\emulator-data)
.\scripts\start-emulators.ps1

# Terminal 2, first run only: seed the parking lots
.\scripts\seed-emulators.ps1

# Terminal 2: start an Android emulator, then run the app against the local backend
.\scripts\run-app.ps1 -Device emulator-5554
```
**On a real Android phone or tablet** (same Wi-Fi as the PC): enable *Developer options → USB debugging* on the device and connect it by USB, then
```powershell
# Terminal 1: emulators that also accept connections from your network
.\scripts\start-emulators.ps1 -Lan
# Terminal 2: the script prints your PC's address; use it here (device ID from `flutter devices`)
.\scripts\run-app.ps1 -EmulatorHost 192.168.1.6 -Device <device-id>
```
Windows blocks incoming connections on networks marked *Public*: allow Java and Node.js when Windows asks, or set your Wi-Fi to *Private* (Settings → Network & internet → Wi-Fi → your network). Only debug builds can talk to the emulators (they use plain HTTP).

The scripts expect JDK 21 at `%USERPROFILE%\tools\jdk-21` and the standalone Firebase CLI at `%USERPROFILE%\tools\firebase.exe` (https://firebase.tools/bin/win/latest), falling back to `java` / `firebase` on PATH. Use `-Fresh` to start with empty data. Stop the emulators with Ctrl+C rather than closing the window, or the data is not saved.

### 1. Prerequisites
* Node.js v20+ & npm
* Java Runtime (JRE / JDK 11+) — *OpenJDK bundled with Android Studio in `Android Studio/jbr` can be used*
* Firebase CLI: `npx firebase-tools`
* Flutter SDK 3.47+ (Dart 3.13+)

### 2. Setting Up Cloud Functions & Firestore Emulator
```bash
# Navigate to functions folder and install dependencies
cd functions
npm install
npm run build
cd ..

# Verify Firestore Emulator setup
npx firebase-tools setup:emulators:firestore
```

### 3. Running Emulator Suite
Start the local Firebase Emulator Suite (Auth on `9099`, Firestore on `8080`, Functions on `5001`, Emulator UI on `4000`). The app talks to the emulators under the project ID of the flavor you run (`dev` → `sps-app-dev`, `prod` → `sps-app-c3f90` per `android/app/src/<flavor>/google-services.json`), so start them with the same project. The functions read `HMAC_SECRET_KEY` as a secret; for the emulator put it in `functions/.secret.local` (git-ignored), otherwise the emulator tries Google Secret Manager and calls fail:
```bash
npx firebase-tools emulators:start --only auth,firestore,functions --project sps-app-dev
```
Seed the lots once per emulator start (admin-only; allowed unauthenticated under the emulator):
```bash
curl -X POST -H "Content-Type: application/json" -d '{"data":{}}' http://127.0.0.1:5001/sps-app-dev/us-central1/migrateLots
```
Access the Emulator Web UI at `http://localhost:4000` to inspect live collections (`parking_lots`, subcollections `slots`, `bookings`, `parking_events`).

Then run the app against the emulators. Sign-in uses the server-side OTP callables (`requestEmailOtp` / `verifyEmailOtp`) and a Firebase Auth custom token; under the emulator the code is also returned to the app and shown on the login screen. `EMULATOR_HOST` defaults to `127.0.0.1` (mapped to `10.0.2.2` on the Android emulator); set it to your machine's LAN IP for a physical device:
```bash
flutter run --flavor dev --dart-define=USE_EMULATORS=true
```

Windows troubleshooting: if the Firestore emulator exits with `Unable to establish loopback connection`, the JVM's socket temp path is too long — set `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\Users\Public\sps-emu` (any short, existing folder). If functions fail to load with `fetch failed`, the runtime started too slowly (common under OneDrive); `start-emulators.ps1` pre-loads them and retries automatically. If the Android emulator shows a blank map or `Failed host lookup` errors, its DNS relay is failing: start it with `-dns-server 8.8.8.8` (the VS Code task already does).

### 4. Running Backend Verification & Concurrency Tests
Run the automated test suite directly against the live Firestore Emulator:
```bash
npx firebase-tools emulators:exec --only firestore "npm test --prefix functions"
```
This suite verifies:
* **Acceptance Criterion 1 (Race Condition Resolution)**: Two simulated clients booking the exact same bay concurrently — atomic transactions guarantee exactly one succeeds and one receives `"Slot just taken — here's the next best"`.
* **Acceptance Criterion 2 (Autonomous Server Auto-Release)**: An expired hold window is released by the server sweeper (`autoReleaseExpiredHolds`) with the app killed.
* **Mathematical Scoring Parity**: 100% mathematical parity against shared JSON test vectors (`test_vectors/scoring_test_vectors.json`).
* **Security Rules Integrity**: Firestore security rules assert that client devices are strictly denied direct writes to slot states, bookings, and audit events.

### 5. Running Flutter Client Tests
```bash
flutter analyze
flutter test --no-pub
```

---

## Design System Guidelines
* **Palette**: Monochrome (`#0A0A0A` text/buttons, `#FFFFFF` surface) with one blue accent (`#2563EB` light, `#3B82F6` dark) reserved strictly for the user's allocated slot and upgrade notifications.
* **Typography**: Google Fonts `Manrope` with tabular figures for real-time counters, timers, and fees.
* Refer to `lib/core/theme/app_theme.dart` for all spacing (`AppSpace`), radius (`AppRadius`), and theme tokens.
