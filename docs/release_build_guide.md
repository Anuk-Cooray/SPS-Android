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

### 4. Grayscale Map Tiles & OpenStreetMap Licensing

The Colombo live route map uses **OpenStreetMap standard tiles**, turned grayscale (inverted in dark mode) with a colour matrix in `colombo_live_map_view.dart` to match the monochrome + blue accent design language. CARTO basemaps were used previously but now require an API key and return placeholder tiles without one.
- **Endpoint**: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`, sent with the app's package name as user agent
- **Attribution**: `© OpenStreetMap contributors` is shown on the map, as the tile usage policy requires
- **Usage policy**: https://operations.osmfoundation.org/policies/tiles/ — fine for development, demos and light use; a public release with many users should switch to a commercial or self-hosted tile provider

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

---

### 7. Deploying the Backend (Auth, Functions, Rules, Email)

> Only needed for a real, internet-facing deployment, which requires the Blaze plan. For development and demos everything runs free on the local emulators; see **Quick start** in the README.

Sign-in is a server-issued email code exchanged for a Firebase Auth custom token, so the backend must be live **before** the matching app build ships. Do every step on `sps-app-dev` first, test with a `dev` build, then repeat on `sps-app-c3f90`.

Prerequisites: the project is on the **Blaze** plan (required for secrets and extensions), and the Firebase CLI is signed in (`firebase login`). On networks that block npm, use the standalone CLI from https://firebase.tools/bin/win/latest in place of `npx firebase-tools`.

#### Step A: Enable Firebase Authentication
In the Firebase console → **Authentication** → **Get started**. No sign-in provider needs to be enabled (custom tokens are always accepted).

#### Step A2: Let the functions mint sign-in tokens
`verifyEmailOtp` calls `createCustomToken`, which signs through IAM in deployed functions. In Google Cloud console → **IAM**, give the functions' runtime service account (`<PROJECT_NUMBER>-compute@developer.gserviceaccount.com` for 2nd-gen functions) the **Service Account Token Creator** role, and make sure the **IAM Service Account Credentials API** is enabled. Without this every login fails with `iam.serviceAccounts.signBlob` permission errors.

#### Step B: Set the HMAC secret
Generate a long random value (never the development value from `functions/.env`) and store it in Secret Manager; the CLI prompts for it:
```bash
firebase functions:secrets:set HMAC_SECRET_KEY --project sps-app-c3f90
```

#### Step C: Install the Trigger Email extension (OTP delivery)
`requestEmailOtp` writes messages to the `/mail` collection; the extension sends them. Have SMTP credentials ready (for example a Gmail app password, SendGrid or Mailgun). The installer prompts for each parameter and stores the SMTP password as a secret:
```bash
firebase ext:install firebase/firestore-send-email --project sps-app-c3f90 --local
```
Answer the prompts with:
| Parameter | Value |
|---|---|
| Firestore Instance Location | the region of your Firestore database |
| SMTP connection URI | e.g. `smtps://username@smtp.gmail.com:465` (no password in the URI) |
| SMTP password | your SMTP / app password |
| Email documents collection | `mail` |
| Default FROM address | e.g. `Smart Parking <no-reply@your-domain>` |

`--local` records the extension in `firebase.json` and `extensions/` so it is deployed together with the functions in Step D.

#### Step D: Deploy functions, rules and the extension
```bash
cd functions && npm ci && npm run build && cd ..
firebase deploy --only functions,firestore:rules,extensions --project sps-app-c3f90
```

#### Step E: Smoke test before releasing the app
Install a `prod` release build on a device, request a code for a real inbox and confirm it arrives within a minute (check the `delivery` field on the `/mail` document if it does not), then book and check in. Under a deployed backend the code is never shown in the app; it only arrives by email.

#### Step F: Release the app
Build the AAB from section 3B with `android/key.properties` in place (section 2). Without that file the release build is signed with the debug key and Google Play rejects it. Users on the previous app version are signed out once and must log in with an email code.
