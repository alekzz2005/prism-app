# AGENTS.md — PRISM (Parenteral Return-demonstration Injection Skills Monitor)

> Paste this file into the root of your `prism-app` Flutter repo.
> Antigravity agents read this automatically at the start of every session.

## Companion Documents

| File | Purpose |
|---|---|
| `AGENTS.md` | *(this file)* Full project spec — architecture, schema, APIs, rules |
| `FRONTEND.md` | UI teammate guide — what to edit, data available, feature extension rules |
| `GIT_WORKFLOW.md` | Branch naming, commit format, PR process — all team members follow this |

---

## Project Identity

**App name:** PRISM
**Platform:** Flutter Android (Dart 3.x, Android 8.0+, minSdkVersion 26)
**Institution:** CIT-U Nursing Department, Cebu, Philippines
**Purpose:** AI-powered parenteral injection technique evaluator for nursing student return-demonstrations (RDs). Detects insertion angle, aspiration technique, and withdrawal angle via MediaPipe; generates clinical AI feedback via Llama 3.3 on OpenRouter; stores sessions in Firebase Firestore.

---

## Tech Stack (do not deviate)

| Layer | Tech |
|---|---|
| UI | Flutter Provider (state management) |
| Computer Vision | `google_mlkit_pose_detection` or `google_mediapipe` Hand Landmarker — 21 landmarks, on-device |
| LLM | Llama 3.3 70B Instruct via OpenRouter API (`https://openrouter.ai/api/v1/chat/completions`) |
| Auth | Firebase Authentication (email + password) |
| Database | Firebase Firestore (NoSQL) |
| HTTP | Dart `http` package |

---

## Folder Structure (target state of `lib/`)

```
lib/
├── main.dart
├── core/
│   └── injection_config.dart        # InjectionConfig model + InjectionConfigService
├── models/
│   └── session_model.dart           # SessionModel (mirrors Firestore sessions schema)
├── providers/
│   ├── session_state_provider.dart  # SessionStateProvider (ChangeNotifier)
│   └── user_role_provider.dart      # UserRoleProvider (ChangeNotifier)
├── services/
│   ├── auth_service.dart            # Firebase Auth wrapper
│   ├── detection_service.dart       # AngleComputationUtil + DetectionService
│   ├── aspiration_detection_service.dart
│   ├── withdrawal_detection_service.dart
│   ├── feedback_service.dart        # FeedbackService + PayloadBuilder
│   ├── openrouter_api_client.dart   # OpenRouterApiClient
│   ├── roster_service.dart          # CSV Parsing and student matching
│   └── live_session_service.dart    # Two-device syncing
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── register_screen.dart
│   ├── student/
│   │   ├── my_sessions_screen.dart      # Student Dashboard with Tabs
│   │   └── session_detail_screen.dart   # Session detail + AI feedback
│   └── instructor/
│       ├── instructor_dashboard_screen.dart  # UC-4.1
│       ├── live_demo_setup_screen.dart       # Remote Session Setup (Desk)
│       ├── remote_control_screen.dart        # Remote Session Controls (Desk)
│       ├── camera_node_screen.dart           # MediaPipe Tracker (Tripod)
│       └── feedback_review_screen.dart       # UC-4.2
└── widgets/
    ├── auth_wrapper.dart             # Routes to role-specific home
    ├── angle_overlay_painter.dart    # CustomPainter for syringe vector overlay
    └── angle_badge.dart              # Pill badge showing live angle
```

---

## Key Landmarks (MediaPipe Hand Landmarker)

| Landmark ID | Body Part | Used For |
|---|---|---|
| L0 | Wrist | Base vector point — all angle calculations |
| Midpoint(L5, L9) | Knuckles | Distal vector point — longitudinal axis for dart-grip (Lizhe 2024) |
| L4 | Thumb tip | Aspiration plunger displacement tracking |

**Angle formula:** `atan2` of the L0 → Midpoint(L5,L9) vector relative to the vertical axis.

---

## Injection Type Targets

| Type | Target Angle | Tolerance |
|---|---|---|
| IM (Intramuscular) | 90° | ±5° |
| SubQ (Subcutaneous) | 45° | ±5° |
| IV (Intravenous) | 15° | ±3° |
| ID (Intradermal) | 10° | ±3° |

These are stored in `InjectionConfig` and loaded into `SessionStateProvider` before detection starts.

---

## Firestore Schema

### `users/{uid}`
```
uid: String (= Firebase Auth UID)
fullName: String
email: String
role: String  // "Student" or "Instructor"
createdAt: Timestamp
emailVerified: bool
```

### `instructor_roster/{instructorId}/students/{docId}`
```
firstName: String
lastName: String
email: String
```

### `live_sessions/{instructorId}`
```
studentName: String
studentEmail: String
injectionType: String
targetAngle: double
phase: String // "waiting" | "insertion" | "aspiration" | "withdrawal" | "completed"
currentAngle: double
```

### `sessions/{sessionId}`
```
sessionId: String (auto-ID)
userId: String (→ users.uid)
timestamp: Timestamp
injectionType: String  // "IM" | "SubQ" | "IV" | "ID"
insertionAngle: double
insertionScore: int  // 1–5
aspirationResult: String  // "Correct" | "Incorrect" | "Not Detected"
aspirationDuration: double  // seconds
motionSmoothness: String  // "Good" | "Low"
withdrawalAngle: double
withdrawalScore: int  // 1–5
correspondenceResult: String  // "Matches" | "Deviates"
angularDelta: double
overallScore: int  // 1–5
aiFeedbackText: String  // original Llama 3.3 output (never overwritten)
feedbackStatus: String  // "Pending" | "Released" | "Feedback Generation Failed"
releaseTimestamp: Timestamp  // null until instructor releases
instructorNote: String  // instructor edits; original aiFeedbackText preserved
flagged: bool
```

---

## Scoring Logic

- Each component (insertion angle, aspiration, withdrawal) maps to a CIT-U 5-point rubric score
- `overallScore` = average of the three component scores, rounded
- Angle accuracy target: MAE ≤ 3° vs. expert annotation
- If a component is undetectable → `flagged = true`, score defaults to 1

---

## Module Build Order (follow this sequence)

1. **Module 3 Auth** — Firebase Auth + `AuthWrapper` + role routing
2. **Module 4 Instructor Setup** — `LiveDemoSetupScreen` + CSV Parsing to `instructor_roster`
3. **Module 1 Detection Engine** — `CameraNodeScreen` (Tripod) syncing angles to `live_sessions` (2Hz)
4. **Module 1 Remote Control** — `RemoteControlScreen` (Desk) managing phase transitions
5. **Module 2 AI Feedback** — `PayloadBuilder` + `OpenRouterApiClient` triggered on Session Complete
6. **Module 3 Student Views** — Tabbed Dashboard (`MySessionsScreen`) + `SessionDetailScreen`

---

## OpenRouter API Call Shape

```dart
POST https://openrouter.ai/api/v1/chat/completions
Headers:
  Authorization: Bearer $OPENROUTER_API_KEY
  Content-Type: application/json
  HTTP-Referer: https://prism.cit-u.edu.ph
  X-Title: PRISM

Body:
{
  "model": "meta-llama/llama-3.3-70b-instruct",
  "messages": [
    {
      "role": "system",
      "content": "You are a clinical nursing education evaluator. Generate structured, specific, encouraging feedback for a nursing student's parenteral injection return demonstration. Keep tone clinical but supportive."
    },
    {
      "role": "user",
      "content": "<PayloadBuilder output — see FeedbackService>"
    }
  ],
  "max_tokens": 500
}
```

---

## Critical Implementation Notes for Agents

1. **MediaPipe on Flutter:** Use `google_mlkit_pose_detection` as fallback if `google_mediapipe` Hand Landmarker Flutter bindings are unavailable. The angle math (atan2 on L0→L8) stays the same.
2. **No video stored:** Only computed metrics go to Firestore. Never upload camera frames.
3. **Firestore security rules:** Students read `sessions` only where `userId == request.auth.uid AND feedbackStatus == "Released"`. Instructors read all sessions.
4. **aiFeedbackText is immutable:** Instructor edits write to `instructorNote` only.
5. **One auto-retry on OpenRouter timeout.** On second failure, save session with `feedbackStatus = "Feedback Generation Failed"`.
6. **State management:** All in-session data lives in `SessionStateProvider`. Clear it on session end before returning to injection type screen.
7. **AuthWrapper** listens to `FirebaseAuth.instance.authStateChanges()` and routes: unauthenticated → LoginScreen, Student role → InjectionTypeScreen, Instructor role → InstructorDashboardScreen.

---

## Wireframe-to-Screen Map

| Screen | File | Feeds From |
|---|---|---|
| Login | `auth/login_screen.dart` | Firebase Auth |
| Register | `auth/register_screen.dart` | Firebase Auth + role field |
| Student Dashboard | `student/my_sessions_screen.dart` | Firestore `sessions` stream (Tabs for types) |
| Session Detail | `student/session_detail_screen.dart` | Single Firestore session doc |
| Instructor Dashboard | `instructor/instructor_dashboard_screen.dart` | Mode selection (Tripod vs Desk) |
| Live Demo Setup | `instructor/live_demo_setup_screen.dart` | CSV file picker, `instructor_roster` stream |
| Remote Control | `instructor/remote_control_screen.dart` | `live_sessions` stream |
| Camera Node | `instructor/camera_node_screen.dart` | `live_sessions` stream + MediaPipe |
| Feedback Review | `instructor/feedback_review_screen.dart` | Firestore release flow |

---

## What Agents Should NOT Do

- Do not generate video recording or upload features
- Do not use `shared_preferences` for auth state — use Firebase Auth stream only
- Do not hardcode API keys — use `--dart-define` or a `.env` approach
- Do not store `InjectionConfig` in Firestore — it is in-memory only
- Do not modify `aiFeedbackText` in Firestore — it is append-only

---

*AGENTS.md v1.0 — PRISM IT332-30, CIT-U, May 2026*
