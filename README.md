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

## YOLOv8 live occupancy integration

The **Main Building Lot** is mapped to the calibrated YOLO camera board. The app
does not run `best.pt` on Android: a local FastAPI server performs inference and
returns the current occupancy board over the LAN.

1. In a separate PowerShell terminal, start the backend (the trained model stays
   in `S:\smart-parking-esp32\best.pt`):

   ```powershell
   cd S:\smart-parking-esp32
   .\.venv\Scripts\python.exe -m uvicorn backend.app:app --host 0.0.0.0 --port 8000
   ```

2. Use the backend dashboard's image upload or camera capture once so a fresh
   inference result exists. A stale or unavailable frame is deliberately shown
   as **Unknown / Offline** and cannot be booked.

3. Run Flutter with the correct backend address. For an Android emulator use
   `10.0.2.2`; for a physical phone, replace the example with the PC's LAN IPv4
   address. Do not commit a personal LAN address.

   ```powershell
   flutter run --dart-define=AI_API_BASE_URL=http://192.168.1.20:8000
   ```

The client refreshes `/api/board` every three seconds. Tapping an available
green slot shows a confirmation prompt, then `POST /api/book/{slot_id}` checks
the current backend state atomically. A 409 conflict is displayed to the user;
occupied, booked, stale, or offline slots cannot be selected. Cancelling a
backend-created booking calls `POST /api/bookings/{booking_ref}/cancel`.

The backend camera calibration is authoritative. Do not reuse the supplied
MetaPKLot polygons with a different camera position; recalibrate on the backend
first.

---

## Design System Guidelines
* **Palette**: Monochrome (`#0A0A0A` text/buttons, `#FFFFFF` surface) with one blue accent (`#2563EB` light, `#3B82F6` dark) reserved strictly for the user's allocated slot and upgrade notifications.
* **Typography**: Google Fonts `Manrope` with tabular figures for real-time counters, timers, and fees.
* Refer to `lib/core/theme/app_theme.dart` for all spacing (`AppSpace`), radius (`AppRadius`), and theme tokens.
