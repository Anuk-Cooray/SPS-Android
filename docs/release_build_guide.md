# Smart Parking System (SLIIT J26-IT-335)
## Production Release Build & Deployment Guide

This guide details the procedure for generating reproducible, cryptographically signed release builds for Android and deploying server-side Cloud Functions and security rules.

---

### 1. Build Flavors & Environment Architecture

The application is structured into two distinct environments via Android `productFlavors` and Dart compile-time defines:

| Environment | Gradle Flavor | Package Identifier | Firebase Project ID | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Development** | `dev` | `com.sliit.smartparking.smart_parking.dev` | `sps-app-dev` | Local testing, emulators, examiner demo tools |
| **Production** | `prod` | `com.sliit.smartparking.smart_parking` | `sps-app-c3f90` | Live staging, defense deployment, release store build |

#### Separate Firebase Configurations
- **Development**: `android/app/src/dev/google-services.json`
- **Production**: `android/app/src/prod/google-services.json`

The Gradle build automatically links the corresponding `google-services.json` based on the targeted flavor.

---

### 2. Cryptographic Signing Setup

Release keystores and credential files are strictly excluded from version control in `.gitignore`:
- `android/key.properties`
- `*.jks`
- `*.keystore`
- `.env`

#### Step A: Generate Android Keystore
Run keytool from your terminal:
```bash
keytool -genkey -v -keystore android/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias sps-release-key
```

#### Step B: Configure `android/key.properties`
Create `android/key.properties` (ignored by git):
```properties
storePassword=<YOUR_STORE_PASSWORD>
keyPassword=<YOUR_KEY_PASSWORD>
keyAlias=sps-release-key
storeFile=../upload-keystore.jks
```

---

### 3. Release Build Commands

#### A. Build Production Release APK
```bash
flutter build apk --flavor prod \
  -t lib/main.dart \
  --dart-define=ENVIRONMENT=prod \
  --dart-define=DEMO_MODE=false \
  --release
```
*Output path:* `build/app/outputs/flutter-apk/app-prod-release.apk`

#### B. Build Production Google Play App Bundle (AAB)
```bash
flutter build appbundle --flavor prod \
  -t lib/main.dart \
  --dart-define=ENVIRONMENT=prod \
  --dart-define=DEMO_MODE=false \
  --release
```
*Output path:* `build/app/outputs/bundle/prodRelease/app-prod-release.aab`

#### C. Build Development / Demo APK
```bash
flutter build apk --flavor dev \
  -t lib/main.dart \
  --dart-define=ENVIRONMENT=dev \
  --dart-define=DEMO_MODE=true \
  --debug
```

---

### 4. Grayscale Map Tiles & CARTO Licensing Compliance

The Colombo live route and bay navigation interface uses **CARTO Positron** grayscale raster tiles to match the system's monochrome + blue accent design language:
- **Endpoint**: `https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png`
- **Subdomains**: `['a', 'b', 'c', 'd']`
- **Attribution**: Displayed on all map instances in accordance with CARTO and OpenStreetMap copyright guidelines:
  `© OpenStreetMap contributors, © CARTO`
- **Terms of Service**: Non-commercial academic research and demonstration usage under CARTO Free Tier and OpenStreetMap ODbL.

---

### 5. Algorithmic Latency Benchmarks (Dart & TypeScript)

Algorithmic latency is measured directly in the real production engines (not Python simulation overhead) over $10^4$ iterations:

| Metric | Dart `ReoptimizationEngine` | Node.js `scoring.ts` | SLA Requirement |
| :--- | :--- | :--- | :--- |
| **Average** | 0.64 µs (0.0006 ms) | 1.48 µs (0.0015 ms) | $< 100$ µs |
| **p50** | 0.00 µs (0.0000 ms) | 1.20 µs (0.0012 ms) | $< 50$ µs |
| **p95** | 2.00 µs (0.0020 ms) | 3.30 µs (0.0033 ms) | $< 1000$ µs |
| **p99** | 4.00 µs (0.0040 ms) | 4.70 µs (0.0047 ms) | $< 1000$ µs (1.0 ms) |

Run Dart benchmark:
```bash
flutter test test/scoring_benchmark_test.dart
```

Run TypeScript benchmark:
```bash
npx mocha -r ts-node/register functions/test/scoring_benchmark.test.ts
```

---

### 6. Reproducibility & Evaluation Commands

To reproduce the scientific evaluation and verify 100% mathematical parity:

```bash
# 1. Verify exact scoring parity against 7 shared test vectors
python -m eval.test_scoring_parity

# 2. Run 30-seed simulation & hypothesis testing (B0, B1, D1, D2, D3 + Sweeps)
python -m eval.run_eval

# 3. Generate publication SVG charts with 95% Confidence Interval error bars
python -m eval.plot_results

# 4. Replay 200 trips against Cloud Functions server authority (Parity <= 5%)
python -m eval.run_system_check
```
