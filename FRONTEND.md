# PRISM — Frontend Developer Guide
# For UI teammates using AI agents (Antigravity, Cursor, Copilot, etc.)

> Read **both** `AGENTS.md` and this file before editing any screen.
> `AGENTS.md` = full project spec. This file = your specific UI guide.

---

## Your Job

The wireframes are the **final UI**. Your job is to make each screen match its wireframe exactly — you can rewrite screens fully to achieve this.

You have **full ownership** of every file in `lib/screens/`. Rewrite them however you need to match the wireframe.

---

## The Only Hard Rules (don't break these)

These are the lines/patterns that wire the app together. You can move them, restructure them, or put them inside different callbacks — but don't delete them or change what they call.

### 1. Navigation calls — keep the destination, change the trigger
```dart
// ✅ You can attach these to any button/gesture you want:
Navigator.push(context, MaterialPageRoute(builder: (_) => DetectionScreen(injectionType: type)));
Navigator.push(context, MaterialPageRoute(builder: (_) => SessionDetailScreen(session: session)));
Navigator.push(context, MaterialPageRoute(builder: (_) => FeedbackReviewScreen(session: session, repo: repo)));
Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => InjectionTypeScreen()), (_) => false);

// ✅ AppBar must still have My Sessions button on InjectionTypeScreen:
Navigator.push(context, MaterialPageRoute(builder: (_) => MySessionsScreen()));
```

### 2. Business logic calls — attach to your wireframe buttons
```dart
// On "Lock Insertion" button:
_lockInsertion();       // detection_screen.dart — don't rename/remove

// On "Start Aspiration" button:
_startAspiration();     // detection_screen.dart — don't rename/remove

// On "Done Aspirating" button:
_lockAspiration();      // detection_screen.dart — don't rename/remove

// On "Lock Withdrawal" button:
_lockWithdrawal();      // detection_screen.dart — don't rename/remove

// On "Complete Session" button:
_completeSession();     // detection_screen.dart — don't rename/remove

// On "Back to Home" button (session_complete_screen):
context.read<SessionStateProvider>().resetSession(); // MUST be called
Navigator.pushAndRemoveUntil(...InjectionTypeScreen()...);

// On "Release to Student" button (feedback_review_screen):
await _releaseService.releaseSession(session.sessionId, _noteController.text.trim());

// On any sign-out button:
await AuthService().signOut();
context.read<UserRoleProvider>().clear();
```

### 3. Firestore queries — keep the filter, change the widget
```dart
// my_sessions_screen.dart — KEEP these exact where() filters:
.where('userId', isEqualTo: uid)
.where('feedbackStatus', isEqualTo: 'Released')

// Don't write to aiFeedbackText — it's immutable
// Instructor edits write to instructorNote only
```

### 4. Widget Keys — keep them for testing
Keep all existing `Key('...')` values. You can add new keys but don't remove these:
```dart
Key('login_email'), Key('login_password'), Key('login_submit'), Key('login_google')
Key('register_name'), Key('register_email'), Key('register_password'), Key('register_submit')
Key('injection_type_IM'), Key('injection_type_SubQ'), Key('injection_type_IV'), Key('injection_type_ID')
Key('my_sessions_button'), Key('student_signout'), Key('instructor_signout')
Key('lock_insertion_button'), Key('start_aspiration_button'), Key('lock_aspiration_button')
Key('lock_withdrawal_button'), Key('complete_session_button'), Key('back_to_home_button')
Key('instructor_note_field'), Key('release_button')
Key('session_tile_${session.sessionId}'), Key('instructor_session_${session.sessionId}')
```

---

## Data Available in Every Screen

Everything you need is already computed and accessible:

### In any screen widget:
```dart
// Current user info:
final role = context.watch<UserRoleProvider>();
role.fullName          // "Juan dela Cruz"
role.isStudent         // bool
role.isInstructor      // bool

// Current session metrics (during detection):
final session = context.watch<SessionStateProvider>();
session.currentConfig?.type          // "IM" | "SubQ" | "IV" | "ID"
session.currentConfig?.targetAngle   // 90.0 | 45.0 | 15.0 | 10.0
session.currentConfig?.tolerance     // 5.0 | 3.0
session.insertionAngle               // double?
session.insertionScore               // int? (1-5)
session.aspirationResult             // "Correct" | "Incorrect" | "Not Detected"
session.aspirationDuration           // double? (seconds)
session.motionSmoothness             // "Good" | "Low"
session.withdrawalAngle              // double?
session.withdrawalScore              // int?
session.correspondenceResult         // "Matches" | "Deviates"
session.angularDelta                 // double?
session.overallScore                 // int?
```

### In DetectionScreen specifically (live detection state):
```dart
_liveAngle            // double — updates every 100ms
_angleInRange         // bool — true when within tolerance
_phase                // DetectionPhase.insertion / .aspiration / .withdrawal
_aspirationElapsed    // double — seconds
_aspirationDisplacement // double — pixels
_lockedInsertionAngle // double? — set after Phase 1
_lockedWithdrawalAngle // double? — set after Phase 3
```

### SessionModel fields (from Firestore, in history screens):
```dart
session.sessionId
session.userId
session.injectionType        // "IM" | "SubQ" | "IV" | "ID"
session.timestamp            // Timestamp → .toDate() → DateTime
session.insertionAngle       // double
session.insertionScore       // int 1-5
session.aspirationResult     // String
session.aspirationDuration   // double
session.motionSmoothness     // String
session.withdrawalAngle      // double
session.withdrawalScore      // int 1-5
session.correspondenceResult // String
session.angularDelta         // double
session.overallScore         // int 1-5
session.aiFeedbackText       // String (READ ONLY — never edit)
session.instructorNote       // String
session.feedbackStatus       // "Pending" | "Released" | "Feedback Generation Failed"
```

---

## File → Wireframe Map

| File to own | Screen | Navigates to |
|---|---|---|
| `screens/auth/login_screen.dart` | Login | InjectionTypeScreen or InstructorDashboardScreen |
| `screens/auth/register_screen.dart` | Register | LoginScreen (pop) |
| `screens/student/injection_type_screen.dart` | Type selection | DetectionScreen |
| `screens/student/detection_screen.dart` | Camera + 3-phase detection | SessionCompleteScreen |
| `screens/student/session_complete_screen.dart` | Results + AI feedback | InjectionTypeScreen |
| `screens/student/my_sessions_screen.dart` | Session history list | SessionDetailScreen |
| `screens/student/session_detail_screen.dart` | Session detail | (back) |
| `screens/instructor/instructor_dashboard_screen.dart` | All sessions | FeedbackReviewScreen |
| `screens/instructor/feedback_review_screen.dart` | Review + release | (back) |

### Adding a new screen
1. Create file in `screens/student/` or `screens/instructor/`
2. Import what you need from the list below
3. Add navigation to it from the appropriate existing screen

---

## Standard Imports

```dart
// Almost every screen needs:
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // for DateFormat

// Data & state:
import '../../providers/session_state_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../models/session_model.dart';
import '../../core/injection_config.dart';

// Services:
import '../../services/auth_service.dart';
import '../../services/feedback_service.dart';
import '../../services/feedback_release_service.dart';
import '../../services/instructor_session_repository.dart';

// Other screens (for navigation):
import '../student/injection_type_screen.dart';
import '../student/detection_screen.dart';
import '../student/session_complete_screen.dart';
import '../student/my_sessions_screen.dart';
import '../student/session_detail_screen.dart';
import '../instructor/instructor_dashboard_screen.dart';
import '../instructor/feedback_review_screen.dart';
```

---

## Adding New Features / Missing Backend

If a wireframe requires a feature that isn't in the current backend, **you are allowed to add it**. Follow these rules:

### Adding a new screen
1. Create the file in `screens/student/` or `screens/instructor/`
2. Add navigation to it from the relevant existing screen
3. Use `SessionModel` fields — no new Firestore fields unless truly needed

### Adding a new service
1. Create it in `lib/services/` following the existing pattern
2. Keep it stateless (no `ChangeNotifier`) — state goes in providers
3. Use `FirebaseFirestore.instance` directly (already initialized)

### Adding a new Firestore field
> Only do this if the feature genuinely requires persisted data.

1. Add the field to `session_model.dart` with a default value in `fromFirestore()`
2. Add it to the `feedback_service.dart` Firestore write in `submitSession()`
3. Tell Emmanuel (backend lead) so `AGENTS.md` can be updated

### Adding a new provider
> Only do this if the state is truly cross-screen and doesn't fit in `SessionStateProvider`.

1. Create it in `lib/providers/` extending `ChangeNotifier`
2. Register it in `lib/main.dart` inside `MultiProvider`

### Can I change the AI prompt?
Yes — it's in `lib/services/feedback_service.dart` in the `PayloadBuilder.buildPrompt()` method. Edit it freely.

### Can I add new packages?
Yes — run `flutter pub add package_name` and commit the updated `pubspec.yaml` and `pubspec.lock`. Follow the branch/commit convention in `GIT_WORKFLOW.md`.

---

## What NOT to Do

| ❌ Don't | Why |
|---|---|
| Edit anything in `lib/services/` | Backend is done — don't touch |
| Edit anything in `lib/providers/` | State management is wired — don't touch |
| Edit `lib/models/session_model.dart` | Mirrors Firestore schema exactly |
| Edit `lib/core/injection_config.dart` | Config is in-memory, not in Firestore |
| Edit `lib/widgets/auth_wrapper.dart` | Routing logic is done |
| Edit `lib/main.dart` | App entry point is wired |
| Write to `aiFeedbackText` | Immutable — instructor writes to `instructorNote` only |
| Add video recording/upload | Out of scope |
| Store anything in `shared_preferences` | Use Firebase stream only |
| Create new Firestore collections or fields | All fields are already in `session_model.dart` |
| Hardcode API keys | Use `--dart-define-from-file=.env.json` |

---

## Running the App

```bash
# Test mode — no API key needed, mock AI feedback:
flutter run --dart-define=USE_MOCK_FEEDBACK=true

# Real AI feedback mode:
flutter run --dart-define-from-file=.env.json
```

---

## Prompt Template for Your AI Agent

```
Read AGENTS.md and FRONTEND.md in this repo first.

Rewrite `lib/screens/student/my_sessions_screen.dart` to match this wireframe:
[paste wireframe image or description]

You have full ownership of the screen file. Rewrite the entire file if needed.

Rules:
- Keep all widget Key() values
- Keep the Firestore query filters (.where('userId'...) .where('feedbackStatus'...))
- Keep navigation: tapping a session → SessionDetailScreen(session: session)
- Keep sign-out logic
- Do not edit files outside lib/screens/
```

---

*PRISM FRONTEND.md v2.0 — IT332-30, CIT-U, May 2026*
*Backend: Emmanuel | UI: teammates*
