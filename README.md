# Smart Parking System (SPS) (00Testingggg00)
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

## Design System Guidelines
* **Palette**: Monochrome (`#0A0A0A` text/buttons, `#FFFFFF` surface) with one blue accent (`#2563EB` light, `#3B82F6` dark) reserved strictly for the user's allocated slot and upgrade notifications.
* **Typography**: Google Fonts `Manrope` with tabular figures for real-time counters, timers, and fees.
* Refer to `lib/core/theme/app_theme.dart` for all spacing (`AppSpace`), radius (`AppRadius`), and theme tokens.
