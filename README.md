# PRISM: Parenteral Return-demonstration Injection Skills Monitor

**PRISM** (`v3.0.0+3`) is a Flutter-based cross-platform mobile application developed for the **Cebu Institute of Technology – University (CIT-U)** Nursing Department (IT411-30 Capstone Project). While built on Flutter's cross-platform framework, the current `v3.0.0-midterm` release is packaged and distributed specifically as an **Android APK** (`minSdkVersion 26`, Android 8.0+).

PRISM assists clinical instructors and nursing students during **Intramuscular (IM) injection return-demonstrations (RDs)** by combining Roboflow-hosted object and keypoint detection, two-device WebRTC/Firestore synchronization, key-phase visual snapshot evidence, and an evidence-grounded **Llama 3.3 70B Instruct** clinical feedback pipeline with post-generation validation and deterministic fallback.

> [!IMPORTANT]
> **Clinical Instructor Authority:** All AI-generated feedback and computer vision measurements in official return-demonstrations are strictly **advisory**. Official session evaluations remain quarantined (`Pending`) and hidden from students until the supervising clinical instructor reviews the captured snapshots and telemetry, optionally edits the feedback draft, and explicitly releases the evaluation.

---

## Key Features & Clinical Workflows

### 1. Two-Device Official Return-Demonstration Workflow (`UC-1.1` – `UC-1.3`, `UC-4.1` – `UC-4.2`)
Official evaluations use two synchronized instructor devices signed into the supervising instructor's account:
* **Camera Node (Tripod — `CameraNodeScreen`)**: Positioned perpendicular to the injection site. Captures camera frames, runs cloud-assisted syringe and arm detection, streams a live ~30 FPS downsampled preview (`360px` JPEG) over a peer-to-peer WebRTC `RTCDataChannel` (`mirror`), publishes 2 Hz angle telemetry and detection-loss status to Cloud Firestore (`live_sessions/{instructorId}`), and captures high-resolution Base64 still snapshots at each locked phase.
* **Remote Control (Desk — `RemoteControlScreen`)**: Operated by the clinical instructor from their desk. Displays the live mirrored camera feed, real-time syringe-to-arm angle, and phase progression controls (**Lock Insertion Angle**, **Aspiration Blood Check**, and **Confirm Needle Withdrawal**). Includes a detection-loss guardrail that disables phase advancement if the syringe or arm leaves the frame for 3 consecutive frames.

### 2. Single-Device Student Self-Practice Mode (`UC-3.4`)
* **Self-Practice (`PracticeModeScreen`)**: Students can practice IM injection technique independently on a single device.
* Displays an anatomical placement guide overlay, tracks insertion and withdrawal angles locally against the $90.0^\circ$ target, records aspiration time and needle stability drift, captures phase snapshots, and immediately generates an advisory **AI Practice Guide** (`isPractice: true`, `feedbackStatus: 'Released'`) labeled *"AI guide for practice, not reviewed by an instructor"*.

### 3. Computer Vision Angle Measurement (`UC-1.1` & `UC-1.3`)
* **Roboflow-Hosted Detection Pipeline (`RoboflowDetectionService`)**: Camera frames are downsampled (`480px` width, JPEG quality `50`) in a background Dart `Isolate` and sent to a configured Roboflow Serverless Workflow endpoint (`ROBOFLOW_WORKFLOW_URL`, with automatic fallback to the hosted Roboflow object detection endpoint).
* **3-Tier Vector Geometry**: Computes the acute/right angle $\theta \in [0^\circ, 90^\circ]$ between the syringe axis vector and the arm surface vector using $\theta = \arccos(|\hat{v}_{\text{syr}} \cdot \hat{v}_{\text{arm}}|) \times \frac{180}{\pi}$:
  1. **Keypoint Vector Mode**: Uses `plunger_top`/`barrel_base` to `needle_tip` keypoints against `arm_top` to `arm_bottom` keypoints when available.
  2. **Syringe + Needle Bounding-Box Mode**: Uses the vector between the detected syringe center and needle tip center.
  3. **Bounding-Box Aspect Ratio Triangulation Fallback**: Approximates syringe inclination from bounding-box dimensions when the fine needle tip is occluded.
* **Temporal Smoothing & Prosthetic Guard**: Smooths live readings over a 7-frame moving average window and automatically rejects prosthetic/mannequin arms (`fake_arm`).

### 4. Aspiration Evaluation & Blood-Return Protocol (`UC-1.2` / `CR-1` / `DEF-5`)
* **Instructor-Observed Blood Check (`AspirationOutcome`)**: Smartphone cameras cannot visually detect intravascular blood flash inside a syringe barrel. Therefore, computer vision **does not** detect blood return; the aspiration rubric score is determined solely by the instructor's (or practicing student's) explicit **Stop / Continue** input:
  * **No Bleeding (`No Bleeding (Proceed to Withdrawal)`)**: Scores **5 / 5** (`flagged = false`) and advances to the withdrawal phase.
  * **Bleeding Detected (`Cancel (Patient Bleeding)`)**: Immediately aborts the session (`createBleedingStoppedSession`), scores **1 / 5** (`overallScore = 1`, `flagged = true`), marks needle withdrawal as **Not performed (session stopped)** (unscored), and assigns a standard clinical abort notice (`bloodSessionGuardText`) without calling the LLM.
  * **Not Recorded (Legacy / Undetected)**: Scores **1 / 5** (`flagged = true`).
* **Supporting Telemetry (Informational Only)**:
  * **Elapsed Aspiration Duration (`aspirationDuration`)**: Tracked by a real-time `100ms` timer (`ValueNotifier<double>`) on the Remote Control and Practice screens.
  * **Needle Stability Drift (`aspirationAngleDrift`)**: Tracks the maximum angular deviation $\max |\theta_{\text{live}} - \theta_{\text{insertion}}|$ across valid frames during aspiration. Neither duration nor drift alters the aspiration rubric score.

### 5. Evidence-Grounded AI Clinical Feedback Pipeline (`UC-2.1` / `CR-2` / `DEF-3`)
* **Llama 3.3 70B Instruct via OpenRouter (`OpenRouterApiClient`)**: Sends structured numerical session telemetry (`PayloadBuilder`) to `meta-llama/llama-3.3-70b-instruct:free` with automatic fallback to `meta-llama/llama-3.3-70b-instruct` (`temperature: 0.3`, `max_tokens: 300`, `20s` timeout per model).
* **Post-Generation Clinical Validator (`FeedbackValidator` & `FeedbackEvidence`)**: Validates every AI response against recorded session facts before saving:
  * **Numeric Whitelist**: Every number in the text must match a recorded or derived session metric in `FeedbackEvidence.allowedNumbers` within $\pm 0.15$ (qualifying CIT-U rubric `"step 19"`, `"step 20"`, and `"step 21"` references).
  * **Aspiration Consistency**: Rejects any contradiction of the recorded `AspirationOutcome` (e.g., claiming blood return on a `No Bleeding` session or claiming safe injection on a `Bleeding Detected` session).
  * **Prohibited Unmeasured Claims**: Rejects hallucinated durations (`"5-10s"`), unmeasured physical traits (`wrist`, `steadiness`, `speed`, `smoothness`, `plunger pressure`, `needle depth`), camera blood-detection claims, and unsupported placement guarantees (`proper placement`, `confirming placement`).
  * **Structure Enforcement**: Requires exactly **4 paragraphs** and **$\le 175$ words**.
* **Single Regeneration Retry & Deterministic Fallback (`DeterministicFeedbackBuilder`)**:
  * If Pass 1 fails validation, `FeedbackService` appends specific correction instructions naming the exact offending numbers or phrases (`FeedbackValidator.getCorrectionInstructions`) and retries **once** (`aiValidationStatus = 'Auto-corrected'`).
  * If Pass 2 also fails validation—or if OpenRouter times out or is unreachable—the system automatically falls back to a rule-based 4-paragraph summary (`DeterministicFeedbackBuilder.build`, `aiValidationStatus = 'Template Fallback'`), ensuring feedback is never empty or hallucinated.

### 6. Instructor Review, Original Draft Preservation, Private Notes & Release Control (`UC-4.2` / `CR-2b`)
* **Editable Student-Facing Feedback (`aiFeedbackText`)**: On `FeedbackReviewScreen`, the instructor can edit the AI draft (with `800ms` debounced draft auto-save before release) prior to releasing it to the student.
* **Immutable Original AI Draft (`aiFeedbackOriginal`)**: The untouched initial output from the AI pipeline is stored permanently in `aiFeedbackOriginal`. Instructors can restore the initial draft at any time via the **Revert** button.
* **Strictly Private Instructor Notes (`instructorNote`)**: Instructors have a dedicated **Private instructor note** field for internal clinical observations. `instructorNote` is never rendered on any student screen and is write-protected against student accounts in `firestore.rules`.
* **Single & Batch Release (`FeedbackReleaseService`)**: Instructors can release evaluations individually from `FeedbackReviewScreen`, in bulk by **Section**, or via **Manual Multi-Selection** on `InstructorDashboardScreen`. Releasing a session sets `feedbackStatus = 'Released'`, stamps `releaseTimestamp`, and dispatches an in-app notification to the student.

### 7. Key-Phase Snapshot Visual Evidence (`UC-3.2` & `UC-4.2` / `CR-3`)
* **Unified Phase Evidence Cards (`SnapshotEvidencePanel`)**: Up to three still JPEG snapshots (`insertionImageBase64`, `aspirationImageBase64`, `withdrawalImageBase64`) are captured at `720px` width and size-capped under 250,000 Base64 characters each (re-encoding at quality `70` if needed) to stay safely within Cloud Firestore's 1 MB document limit.
* Displayed directly above each phase's numerical measurements on both `FeedbackReviewScreen` (for instructors) and `SessionDetailScreen` (for students, only after `feedbackStatus == 'Released'`), with full-screen pinch-to-zoom inspection (`ImageZoomDialog`) and graceful placeholders (`"Snapshot not captured"` or `"Not performed"`).
* **Privacy**: No video or audio streams are ever recorded or stored.

### 8. Section & Student Roster Management (`UC-4.1`)
* **Multi-Format Roster Import (`RosterService`)**: Instructors can create class sections (`instructor_roster/{instructorId}/sections/{sectionId}`) and import student rosters from **`.csv`, `.xlsx`, and `.xls`** files (via `file_picker`, `csv`, and `excel` packages) or add/edit students manually (`SectionStudentsScreen`).
* **Email Uniqueness & Archiving**: Student deduplication is enforced strictly by lowercase email address per section. Supports soft-archiving, restoring, and permanent deletion of archived student records.

---

## CIT-U Intramuscular (IM) Scoring Rubric

PRISM evaluates Intramuscular (IM) injection technique against a **$90.0^\circ$ target angle** (`±5.0°` tolerance):

| Phase / Component | Metric Evaluated | CIT-U 5-Point Rubric Mapping (`RoboflowDetectionService.scoreIMAngle` & `AspirationOutcome`) |
| :--- | :--- | :--- |
| **1. Needle Insertion (Step 19)** | Deviation $\Delta_{\text{ins}} = \|\theta_{\text{insertion}} - 90.0^\circ\|$ | • **5**: $\Delta_{\text{ins}} \le 0.5^\circ$<br>• **4**: $0.5^\circ < \Delta_{\text{ins}} \le 5.0^\circ$<br>• **3**: $5.0^\circ < \Delta_{\text{ins}} \le 10.0^\circ$<br>• **2**: $10.0^\circ < \Delta_{\text{ins}} \le 15.0^\circ$<br>• **1**: $\Delta_{\text{ins}} > 15.0^\circ$ *(Flagged)* |
| **2. Aspiration (Step 20)** | Instructor / Student Blood Check Decision (`AspirationOutcome`) | • **5**: `No Bleeding` (`bleedingObserved == false`)<br>• **1**: `Bleeding Detected` (`bleedingObserved == true`, session stopped immediately, `overallScore = 1`, *Flagged*) or `Not Recorded` (*Flagged*)<br>*(Note: Elapsed `aspirationDuration` and `aspirationAngleDrift` are recorded as supporting evidence only and do not alter the score.)* |
| **3. Needle Withdrawal (Step 21)** | Deviation $\Delta_{\text{wth}} = \|\theta_{\text{withdrawal}} - 90.0^\circ\|$ & Angular Delta $\Delta\theta = \|\theta_{\text{withdrawal}} - \theta_{\text{insertion}}\|$ | • Scored 1–5 using the same $90.0^\circ$ deviation bands as Insertion.<br>• **Correspondence Cap**: If $\Delta\theta \le 5.0^\circ$ (`Matches`), full score is retained; if $\Delta\theta > 5.0^\circ$ (`Deviates`), `withdrawalScore` is capped at a maximum of **3 / 5**.<br>• Not performed or scored if session was stopped for bleeding during aspiration. |
| **Overall Session Score** | Rounded mean of the 3 component scores | • Normal completion: $\text{round}((\text{insertionScore} + \text{aspirationScore} + \text{withdrawalScore}) / 3)$<br>• Bleeding abort: Forced to **1 / 5** (`flagged = true`). |

---

## System Architecture & Technology Stack

### Technology Stack

| Layer | Technology / Package | Purpose |
| :--- | :--- | :--- |
| **Mobile Framework** | Flutter `3.41.9` / Dart `^3.11.5` | Cross-platform UI framework; packaged as an Android APK (`minSdk = 26`, JDK 17). |
| **State Management** | `provider` (`^6.1.5+1`) | Role and authentication state routing (`UserRoleProvider`, `AuthWrapper`). |
| **Authentication** | `firebase_auth` (`^6.0.0`), `google_sign_in` (`^6.2.1`) | Email/password sign-in, student registration with email verification, password reset, and Google OAuth. |
| **Database & Signaling** | `cloud_firestore` (`^6.0.0`), `firebase_core` (`^4.0.0`) | NoSQL storage for `users`, `sessions`, `instructor_roster`, `notifications`, and `live_sessions` (2 Hz telemetry + WebRTC signaling). |
| **Peer-to-Peer Streaming** | `flutter_webrtc` (`^1.6.0`) | `RTCPeerConnection` (STUN: `stun:stun.l.google.com:19302`) and `RTCDataChannel` (`mirror`) for live camera preview & snapshot transfer between Camera Node and Remote Control. |
| **Computer Vision** | `camera` (`^0.11.1`), `image` (`^4.3.0`), `http` (`^1.2.2`) | Camera stream capture, background `Isolate` JPEG encoding, and Roboflow Workflow API inference (`RoboflowDetectionService`). |
| **Clinical AI (LLM)** | OpenRouter REST API (`http`) | `meta-llama/llama-3.3-70b-instruct:free` and `meta-llama/llama-3.3-70b-instruct` with `FeedbackValidator` and `DeterministicFeedbackBuilder`. |
| **Roster Import** | `file_picker` (`^11.0.2`), `csv` (`^8.0.0`), `excel` (`^4.0.6`) | Importing student rosters from `.csv`, `.xlsx`, and `.xls` spreadsheets. |

### Repository Structure (`lib/` & `test/`)

```text
lib/
├── main.dart                                 # App entry point, Firebase & AppEnv init, MultiProvider
├── core/
│   ├── app_env.dart                          # Compile-time --dart-define environment accessors
│   ├── aspiration_outcome.dart               # AspirationOutcome, scoring rule, blood-stop session builder
│   └── injection_config.dart                 # IM target angle (90.0°) & tolerance (±5.0°)
├── models/
│   ├── notification_model.dart               # In-app notification model
│   └── session_model.dart                    # Firestore sessions/{sessionId} data model (27 fields)
├── providers/
│   ├── session_state_provider.dart           # Legacy provider (retained for compatibility)
│   └── user_role_provider.dart               # Authenticated user UID, name, role, verification state
├── services/
│   ├── auth_service.dart                     # Firebase Auth & Google Sign-In wrapper
│   ├── deterministic_feedback_builder.dart   # Rule-based 4-paragraph clinical summary fallback
│   ├── feedback_evidence.dart                # Extracts measured telemetry & allowedNumbers whitelist
│   ├── feedback_exceptions.dart              # Typed timeout & API exceptions
│   ├── feedback_release_service.dart         # Single & batch release + student notification dispatch
│   ├── feedback_service.dart                 # PayloadBuilder + 2-pass LLM generation/validation/fallback
│   ├── feedback_validator.dart               # Post-generation clinical validator & correction builder
│   ├── instructor_session_repository.dart    # Official session streaming, draft saving, deletion
│   ├── live_session_service.dart             # Two-device Firestore telemetry & phase synchronization
│   ├── notification_service.dart             # Firestore user notifications & local preference toggle
│   ├── openrouter_api_client.dart            # OpenRouter Llama 3.3 70B free-to-paid cascade client
│   ├── roboflow_service.dart                 # Isolate JPEG encoding, Roboflow API, vector angle math
│   ├── roster_service.dart                   # Section CRUD & CSV/XLSX/XLS student roster import
│   └── webrtc_signaling_service.dart         # Firestore SDP offer/answer & ICE candidate signaling
├── screens/
│   ├── auth/                                 # Login, Register, EmailVerification, ForgotPassword
│   ├── instructor/                           # InstructorDashboard, SectionStudents, CameraNode, RemoteControl, FeedbackReview
│   ├── student/                              # MySessions, SessionDetail, PracticeMode
│   └── shared/                               # Profile, ChangePassword
└── widgets/
    ├── auth_wrapper.dart                     # Role-based root router
    ├── detection_overlay_painter.dart        # Bounding-box overlay painter for arm & syringe
    ├── image_zoom_dialog.dart                # Pinch-to-zoom full-screen snapshot gallery modal
    ├── notification_center_sheet.dart        # In-app notification bottom sheet
    └── snapshot_evidence_panel.dart          # Unified 3-phase snapshot + measurement cards

test/
├── aspiration_outcome_test.dart              # 13 unit tests for AspirationOutcome & bleeding stop
├── feedback_prompt_test.dart                 # 6 unit tests for PayloadBuilder prompt formatting
├── feedback_service_test.dart                # 5 unit tests for AI failure fallback & student labels
├── feedback_validator_test.dart              # 13 unit tests for FeedbackValidator & deterministic builder
└── widget_test.dart                          # 1 smoke test
```

### Security & Pre-Release Quarantine (`firestore.rules`)
* **Pre-Release Quarantine**: Students can read `sessions/{sessionId}` documents **only** when `feedbackStatus == 'Released'` and the session belongs to their account (`userId == request.auth.uid || userId == request.auth.token.email`). Unreleased (`Pending` or `Feedback Generation Failed`) sessions are quarantined at both the Firestore security rule level and the client query level.
* **Write Restrictions**: Only authenticated instructors (`role == 'Instructor'`) can create, update, or delete official sessions and access `live_sessions/**` or `instructor_roster/**`. Students may only create their own self-practice sessions (`isPractice == true`, `feedbackStatus == 'Released'`) and update the four AI feedback fields (`aiFeedbackText`, `aiFeedbackOriginal`, `aiValidationStatus`, `aiValidationNotes`) on those practice sessions.

---

## Setup, Development & Release Build Instructions

### Prerequisites
* **Flutter SDK**: `3.x` (`3.41.9` stable verified) with **Dart SDK** `^3.11.5`
* **Java Development Kit (JDK)**: Version `17`
* **Android SDK**: API Level `34` (targeting `minSdk = 26`, Android 8.0+)
* **Physical Android Device(s)**: Android 8.0+ with rear camera and USB debugging enabled (two devices required for official Tripod + Remote Control workflow; one device for Student Practice Mode)

### 1. Firebase Configuration
1. Obtain `google-services.json` from the Firebase Console (`prism-app-ae2d6`).
2. Place it at:
   ```text
   android/app/google-services.json
   ```
   *(A sanitized template is provided at `android/app/google-services.json.example`. Never commit `google-services.json` to Git.)*

### 2. Environment Configuration (`.env.json`)
PRISM uses compile-time environment injection via `--dart-define-from-file=.env.json` (`AppEnv` in `lib/core/app_env.dart`) so no `.env` file is bundled as a static Flutter asset.

1. Copy `.env.json.example` to `.env.json` in the repository root:
   ```bash
   cp .env.json.example .env.json
   ```
2. Populate `.env.json` with your credentials:
   ```json
   {
     "OPENROUTER_API_KEY": "your-openrouter-api-key-here",
     "ROBOFLOW_API_KEY": "your-roboflow-api-key-here",
     "ROBOFLOW_WORKFLOW_URL": "your-roboflow-workflow-url-here"
   }
   ```
   *(Optional: pass `"USE_MOCK_FEEDBACK": true` or `--dart-define=USE_MOCK_FEEDBACK=true` to use local deterministic feedback without calling OpenRouter.)*

### 3. Running the App in Development
Launch using the root helper script (`run.ps1` / `run.bat`):
```powershell
.\run
```
Or run directly via the Flutter CLI:
```bash
flutter run --dart-define-from-file=.env.json
```

> [!WARNING]
> Running plain `flutter run` without `--dart-define-from-file=.env.json` leaves `ROBOFLOW_API_KEY`, `ROBOFLOW_WORKFLOW_URL`, and `OPENROUTER_API_KEY` empty, which will prevent live Roboflow CV detection and OpenRouter LLM calls from functioning.

### 4. Building the Reproducible Release APK
Automated scripts verify `.env.json`, compile the release APK with `--dart-define-from-file=.env.json`, copy the artifact to `dist/prism-v3.0.0-midterm.apk`, and print its SHA-256 hash:

**Windows (PowerShell):**
```powershell
.\scripts\build_release.ps1
```

**macOS / Linux (Bash):**
```bash
chmod +x ./scripts/build_release.sh
./scripts/build_release.sh
```

* **Compiler Output**: `build/app/outputs/flutter-apk/app-release.apk`
* **Staged Release Artifact**: `dist/prism-v3.0.0-midterm.apk`

For full deployment, signing, and Firestore rules publishing instructions, see [DEPLOYMENT.md](DEPLOYMENT.md).

---

## Testing & Static Analysis Verification

Run the automated test suite and static analyzer from the repository root:

```bash
flutter test --reporter expanded
flutter analyze
```

### Current Verified Audit Results (`v3.0.0+3` / `main` @ `c4c70df` / `bb97ff0`)

| Verification Check | Command | Result | Details |
| :--- | :--- | :--- | :--- |
| **Unit & Widget Tests** | `flutter test --reporter expanded` | **38 Passed / 0 Failed / 0 Skipped** (`Exit Code: 0`) | • `test/aspiration_outcome_test.dart`: **13 passed**<br>• `test/feedback_prompt_test.dart`: **6 passed**<br>• `test/feedback_service_test.dart`: **5 passed**<br>• `test/feedback_validator_test.dart`: **13 passed**<br>• `test/widget_test.dart`: **1 passed** |
| **Dart Security Regression Tests** | `flutter test test/security_access_control_test.dart` | **23 Passed / 0 Failed / 0 Skipped** (`Exit Code: 0`) | Verifies access control models, role routing boundaries, and private instructor note isolation logic. |
| **Firestore Emulator Security Tests** | `firebase emulators:exec --only firestore --project prism-app-ae2d6 "node --test test/firestore_rules/firestore_rules.test.mjs"` | **24 Passed / 0 Failed / 0 Skipped** (`Exit Code: 0`) | Comprehensive verification of `firestore.rules` covering user creation/updates, pre-release quarantine, private note subcollections, live sessions, and roster isolation. |
| **Static Analysis** | `flutter analyze` | **0 Errors / 42 Warnings / 30 Info** | Zero compilation or type errors. The 42 warnings and 30 informational messages consist of non-blocking lint notices (unused legacy imports/fields and style hints). |

---

## Known Limitations & Disclosures

1. **Instructor-Dependent Blood Observation (`CR-1`)**: Computer vision does not detect blood flash inside the syringe hub. Aspiration scoring relies on the clinical instructor's (or practicing student's) Stop/Continue button input, while CV and timers record needle angle drift and duration as supporting evidence.
2. **Internet Connectivity & Cloud CV Frame Rate**: Both Roboflow CV detection (~5 FPS on Camera Node, ~10 FPS in Practice Mode) and OpenRouter Llama 3.3 feedback generation require an active internet connection. If OpenRouter is unreachable, PRISM automatically falls back to `DeterministicFeedbackBuilder`.
3. **Android-Only Verified Release Distribution**: Although built with Flutter (and containing an experimental unsigned iOS CI workflow in `.github/workflows/ios_unsigned_build.yml`), only **Android 8.0+ (`minSdk = 26`)** has been hardware-verified and packaged for the `v3.0.0-midterm` release. iOS distribution is unverified and out of scope for this release.
4. **Client-Side Compile-Time Keys & Debug Signing Default**: Values injected via `--dart-define-from-file=.env.json` are compiled into the client binary; evaluation builds use dedicated, spend-capped, revocable API keys. When `android/key.properties` is absent, `android/app/build.gradle.kts` defaults to the Android debug signing configuration so registered Firebase Google Sign-In SHA-1 fingerprints work out of the box for evaluators.
5. **Private Clinical Instructor Notes**: Private instructor notes are stored exclusively in the instructor-only subcollection `sessions/{sessionId}/private/instructor_note` and are write- and read-restricted to instructors in `firestore.rules`. Legacy public notes on `sessions/{sessionId}` are migrated and cleared prior to student access, ensuring private notes are never exposed in student-readable session documents.
