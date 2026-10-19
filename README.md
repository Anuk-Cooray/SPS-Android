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
Start the local Firebase Emulator Suite (Firestore on `8080`, Functions on `5001`, Emulator UI on `4000`):
```bash
npx firebase-tools emulators:start --only firestore,functions
```
Access the Emulator Web UI at `http://localhost:4000` to inspect live collections (`parking_lots`, subcollections `slots`, `bookings`, `parking_events`).

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
