# PRISM Deployment and Release Guide

This guide details the reproducible build, verification, and deployment process for the PRISM (Parenteral Return-demonstration Injection Skills Monitor) Android application (`v3.0.0-midterm`).

---

## 1. Overview

PRISM is distributed directly as an Android APK via GitHub Releases with a mirrored Google Drive backup for evaluators. The application is not published to Google Play Store.

- **Target Version:** `3.0.0+3`
- **Release Tag:** `v3.0.0-midterm`
- **Distribution Artifact:** `dist/prism-v3.0.0-midterm.apk`
- **Platform:** Android 8.0+ (minSdkVersion 26, targetSdkVersion 34)

---

## 2. Prerequisites

Ensure the following tools are installed on your build workstation:

- **Flutter SDK:** Version 3.x (Dart 3.x) on the `stable` channel.
- **Android SDK:** Command-line tools and platform API 34 installed.
- **Java Development Kit (JDK):** Version 17.
- **Shell Environment:** PowerShell 5.1+ (Windows) or Bash 4+ (macOS/Linux).
- **Physical Android Device or Emulator:** With Developer Options and USB Debugging enabled.

Verify your environment with:
```bash
flutter doctor
```

---

## 3. One-Time Setup

### 3.1. Firebase Configuration
1. Obtain the project's `google-services.json` from the Firebase Console (`prism-app-ae2d6`).
2. Place the file at:
   ```
   android/app/google-services.json
   ```
   *(A reference template is available at `android/app/google-services.json.example`).*

### 3.2. Environment Configuration
1. Copy the example environment file to the repository root:
   ```bash
   cp .env.json.example .env.json
   ```
2. Populate `.env.json` with your API credentials:
   ```json
   {
     "OPENROUTER_API_KEY": "your-openrouter-api-key-here",
     "ROBOFLOW_API_KEY": "your-roboflow-api-key-here",
     "ROBOFLOW_WORKFLOW_URL": "your-roboflow-workflow-url-here"
   }
   ```

> [!CAUTION]
> Neither `android/app/google-services.json` nor `.env.json` must ever be committed to git. Both are explicitly ignored by `.gitignore`.

---

## 4. Run in Development

### 4.1. Full Live Mode (with API Keys)
Run the application with credentials passed via `--dart-define-from-file`:
```bash
flutter run --dart-define-from-file=.env.json
```

### 4.2. Mock Mode (No External Keys Required)
Run the application in standalone mock mode:
```bash
flutter run --dart-define=USE_MOCK_FEEDBACK=true
```
In mock mode, feedback evaluation uses local deterministic rule-based evaluation without calling OpenRouter or Roboflow endpoints.

---

## 5. Build Reproducible Release APK

PRISM provides automated build scripts that validate configuration, compile the release bundle, stage the output in `dist/`, and output the SHA-256 integrity checksum.

### On Windows (PowerShell)
```powershell
.\scripts\build_release.ps1
```

### On Linux / macOS (Bash)
```bash
chmod +x ./scripts/build_release.sh
./scripts/build_release.sh
```

Both scripts perform the following steps:
1. Verify that `.env.json` exists in the repository root.
2. Ensure the `dist/` output directory exists.
3. Execute `flutter build apk --release --dart-define-from-file=.env.json`.
4. Copy `build/app/outputs/flutter-apk/app-release.apk` to `dist/prism-v3.0.0-midterm.apk`.
5. Compute and print the SHA-256 hash.

---

## 6. Verify Build Artifact

### 6.1. Verify SHA-256 Checksum
Compute the SHA-256 hash of the generated APK:

**Windows (PowerShell):**
```powershell
Get-FileHash -Path dist/prism-v3.0.0-midterm.apk -Algorithm SHA256
```

**macOS / Linux:**
```bash
sha256sum dist/prism-v3.0.0-midterm.apk || shasum -a 256 dist/prism-v3.0.0-midterm.apk
```

### 6.2. Install on Device via ADB
Connect an Android device with USB debugging enabled and run:
```bash
adb install -r dist/prism-v3.0.0-midterm.apk
```

---

## 7. Release and Distribution Steps

1. **Tag the Release:**
   ```bash
   git tag -a v3.0.0-midterm -m "PRISM v3.0.0 Midterm Release"
   git push origin v3.0.0-midterm
   ```

2. **Publish GitHub Release:**
   - Go to **GitHub** -> **Releases** -> **Draft a new release**.
   - Select tag `v3.0.0-midterm`.
   - Title: `PRISM v3.0.0 Midterm Evaluation Release`.
   - Attach binary: `dist/prism-v3.0.0-midterm.apk`.
   - In description, paste the computed SHA-256 hash and changelog summary.

3. **Google Drive Mirror:**
   - Upload an identical copy of `dist/prism-v3.0.0-midterm.apk` to the project Google Drive backup folder for evaluators.

---

## 8. Evaluator Installation Instructions

For evaluators installing PRISM on physical Android hardware:

1. Download `prism-v3.0.0-midterm.apk` from the GitHub Release or the provided Google Drive link.
2. In Android Settings, ensure installation from unknown sources is permitted for your browser or file manager.
3. Tap the downloaded APK to install.
4. Launch **PRISM** and grant Camera permissions when prompted during injection return-demonstration tracking.

---

## 9. Demo Account Handling

Evaluator test accounts for Student and Instructor roles:
- Demo credentials (email and password) are provided privately in the evaluation submission document.
- **Never** commit demo passwords, credentials, or private instructor accounts into this repository.

---

## 10. Publishing Firestore Rules

Whenever database security rules are updated:

1. Open the [Firebase Console](https://console.firebase.google.com/).
2. Select the PRISM project (`prism-app-ae2d6`).
3. Navigate to **Firestore Database** -> **Rules** tab.
4. Copy and paste the entire contents of repository [firestore.rules](file:///d:/GitHub%20Repositories/prism-app/firestore.rules).
5. Click **Publish** to deploy the rules immediately.

---

## 11. Security & Signing Notes

1. **Client-Side Key Hygiene:** Keys supplied via `--dart-define` or `.env.json` are embedded in the compiled APK binary. Dedicated, spend-capped API keys must be used for evaluation builds and revoked following testing.
2. **Signing Configuration:**
   - By default, the build uses the Android debug signing configuration registered with Firebase SHA-1 fingerprints, allowing Google Sign-In and Firebase Auth to work seamlessly out of the box.
   - For custom production signing, create an `android/key.properties` file referencing a production keystore. When present, `android/app/build.gradle.kts` automatically loads and applies it.

---

## 12. Troubleshooting

| Issue | Cause | Resolution |
|---|---|---|
| `Error: .env.json not found` | Build script cannot locate `.env.json` | Copy `.env.json.example` to `.env.json` in repo root and populate keys. |
| `ApiException: 10` on Google Sign-In | SHA-1 certificate mismatch | Ensure the device is running an APK signed with the registered certificate fingerprint. |
| AI Feedback generation fails / times out | Network blockage or invalid OpenRouter API key | Check internet connectivity or run with `--dart-define=USE_MOCK_FEEDBACK=true`. PRISM will automatically display deterministic fallback feedback. |
| Camera preview black or frozen | Missing runtime camera permission | Open Android App Info for PRISM and grant Camera permission manually. |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Signature conflict with previously installed build | Uninstall any older version of PRISM from the device before installing the release APK (`adb uninstall com.example.prism_app`). |
