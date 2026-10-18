# PRISM Midterm Change Log

## CR-1 — CR-1 Aspiration: instructor stop/continue decision as the aspiration score (SO 1.3)
- Validation finding / Specific Objective:
  - Validation finding: Aspiration evaluation had the lowest instructor agreement (73.3%). Camera vision cannot detect intravascular blood flash in the syringe barrel.
  - Specific Objective: SO 1.3 — Evaluate aspiration technique alignment with CIT-U Intramuscular Injection Return-Demonstration rubric (Step 19–21).
- Branch / PR:
  - Branch: `feature/aspiration/bleeding_stop_continue`
- Summary of change:
  - Created single source of truth helper `AspirationOutcome` (`noBleeding`, `bleedingDetected`, `notRecorded`) and scoring rule function `aspirationScore` (noBleeding = 5, bleedingDetected/notRecorded = 1 & flagged).
  - Tracked needle stability during aspiration on camera node by measuring maximum angular drift (`max |liveAngle - lockedInsertionAngle|`) during valid frames, publishing `aspirationAngleDrift` to `live_sessions` (information-only, does not alter score).
  - Added `aspirationScore`, `bleedingObserved`, and `aspirationAngleDrift` to `SessionModel` and Firestore session documents with backward-compatible defaults for legacy documents.
  - Implemented real elapsed aspiration timer on `RemoteControlScreen` with `Key('aspiration_timer')` and persisted real duration (> 0s) on both Continue and Stop paths; replaced fabricated values in practice mode.
  - Unified aspiration outcome display and AI prompt payload across `RemoteControlScreen`, `FeedbackReviewScreen`, `SessionDetailScreen`, `PracticeModeScreen`, and `FeedbackService`.
  - Added button keys `Key('aspiration_stop_button')` and `Key('aspiration_continue_button')`.
  - Added comprehensive unit tests in `test/aspiration_outcome_test.dart`.
- SRS impact (UC ids + new/changed requirement wording):
  - UC-1.2: The instructor's stop/continue decision determines blood presence; the camera does not detect blood. Needle stability during aspiration is recorded and presented as supporting evidence only. The CIT-U rubric defines no aspiration timing or angle bands, so neither is scored.
- SDD impact (components added/changed, data design fields):
  - Added `lib/core/aspiration_outcome.dart` (`AspirationOutcome` enum and pure scoring function).
  - Updated `LiveSessionModel` and `LiveSessionService` to store and publish `aspirationAngleDrift`.
  - Updated `SessionModel` (`aspirationScore: int`, `bleedingObserved: bool?`, `aspirationAngleDrift: double?`).
  - Updated `CameraNodeScreen` to track max drift during aspiration.
  - Updated `RemoteControlScreen`, `PracticeModeScreen`, `FeedbackReviewScreen`, `SessionDetailScreen`, and `FeedbackService`.
- Files changed:
  - `lib/core/aspiration_outcome.dart`
  - `lib/services/live_session_service.dart`
  - `lib/screens/instructor/camera_node_screen.dart`
  - `lib/models/session_model.dart`
  - `lib/screens/instructor/remote_control_screen.dart`
  - `lib/screens/student/practice_mode_screen.dart`
  - `lib/screens/instructor/feedback_review_screen.dart`
  - `lib/screens/student/session_detail_screen.dart`
  - `lib/services/feedback_service.dart`
  - `test/aspiration_outcome_test.dart`
  - `CHANGE_LOG.md`
- New/changed Firestore fields:
  - `sessions/{sessionId}.aspirationScore`: `int` (5 if no bleeding, 1 if bleeding detected or not recorded)
  - `sessions/{sessionId}.bleedingObserved`: `bool?` (false if no bleeding, true if bleeding detected, null if not recorded)
  - `sessions/{sessionId}.aspirationAngleDrift`: `double?` (max needle angle deviation in degrees during aspiration)
  - `live_sessions/{instructorId}.aspirationAngleDrift`: `double?` (live session sync)
- Widget Keys added:
  - `Key('aspiration_timer')`: Live aspiration timer display on remote control.
  - `Key('aspiration_stop_button')`: Stop / Bleeding Detected button.
  - `Key('aspiration_continue_button')`: Continue / No Bleeding button.
- Acceptance criteria (testable, pass/fail):
  - The same session shows the same aspiration outcome and score on remote, review, student detail and in the AI prompt, including legacy 'Not Detected'.
  - Stop → 1 and flagged, session ends as today. Continue → 5. Needle drift is stored and shown but never changes the score.
  - `aspirationDuration` equals the on-screen timer (> 0); no fabricated values remain.
  - SRS impact: UC-1.2 states that the instructor's stop/continue decision determines blood presence, the camera does not detect blood, and needle stability during aspiration is recorded as supporting evidence only. The rubric defines no aspiration timing or angle bands, so none are scored.
  - Test cases for STD: Stop path; Continue path; detection lost during aspiration; legacy document display.
- Suggested test cases (for STD / RTM):
  - TC-CR1-01: Instructor presses "Cancel (Patient Bleeding)" during aspiration -> session fails immediately, `aspirationScore` = 1, `flagged` = true, real duration recorded, `bleedingObserved` = true.
  - TC-CR1-02: Instructor presses "No Bleeding (Proceed to Withdrawal)" -> proceeds to withdrawal, `aspirationScore` = 5, `flagged` = false, real duration recorded, `bleedingObserved` = false.
  - TC-CR1-03: Detection lost during aspiration -> camera node ignores lost frames for drift calculation; drift reflects max valid frame deviation; guardrail disables continue button until syringe re-acquired.
  - TC-CR1-04: Legacy document with `aspirationResult: 'Not Detected'` -> displays score 1/5, flagged banner, "Instructor blood check: Not recorded", and AI prompt states "Outcome was not recorded" without mentioning blood return.
- Evidence to capture (screenshots/logs):
  - Remote control screen displaying `Key('aspiration_timer')` and action buttons.
  - Instructor review screen displaying "Instructor blood check", "Needle stability during aspiration", "Aspiration time", and rubric score.
  - Student session detail screen displaying matching aspiration section and score.
  - Firestore document showing `aspirationScore`, `bleedingObserved`, `aspirationAngleDrift`, and `aspirationDuration`.
- Known limitations:
  - Camera vision does not detect blood return directly; relies on instructor clinical observation via stop/continue input.
  - Needle stability drift is null if syringe detection is lost for the entire aspiration phase.

## CR-2 — CR-2 AI feedback validation rules (SO 2.1)
- Superseded by CR-2b for the instructor edit flow (aiFeedbackText is editable before release; aiFeedbackOriginal keeps the draft; instructorNote is private).
- Validation finding / Specific Objective:
  - Validation finding: Instructors corrected technical details, timing information, and procedural explanations in generated AI feedback. Feedback made unsupported claims about unrecorded durations ("5-10s"), unmeasured physical traits (wrist steadiness, speed, smoothness), and camera-detected blood return.
  - Specific Objective: SO 2.1 — Validate AI clinical feedback against recorded telemetry, CIT-U rubrics, and instructor decisions to eliminate hallucinations and ensure factual clinical grounding.
- Branch / PR:
  - Branch: `feature/feedback/ai_validation_rules`
- Summary of change:
  - Built pure-Dart `FeedbackEvidence` model extracting only measured and instructor-decided facts along with an `allowedNumbers` whitelist.
  - Rewrote system prompt with strict negative constraints (only payload numbers, no durations unless given, blood confirmed only by instructor, no unmeasured physical terms, exactly 4 paragraphs, <= 175 words) and fixed `PayloadBuilder` to omit duration/drift when unrecorded and eliminate the ungrounded "5-10s" claim.
  - Implemented `FeedbackValidator` verifying numeric tokens against allowed numbers (+-0.05), blood assertions against `AspirationOutcome`, prohibited physical terms, and 4-paragraph / 175-word structure.
  - Added single-retry regeneration with violation corrections and a deterministic rule-based fallback draft (`DeterministicFeedbackBuilder`), recording `aiValidationStatus` and `aiValidationNotes`. Updated mock mode to return the deterministic draft.
  - Enforced `aiFeedbackText` immutability by preventing release operations from modifying it; routed instructor edits to `instructorNote` and displayed `instructorNote` (or original AI text) to students; stopped leaking raw exception strings.
  - Restricted OpenRouter cascade strictly to Llama 3.3 70B (free variant then paid) with 1500ms backoff and reduced temperature to 0.3.
  - Added validation status badge on `FeedbackReviewScreen` (`Key('ai_validation_badge')`) showing "Validated" (green), "Auto-corrected" (amber), or "Template draft — review closely" (amber).
  - Added unit test suites `test/feedback_validator_test.dart` and `test/feedback_prompt_test.dart`.
- SRS impact (UC ids + new/changed requirement wording):
  - UC-2.1: The system shall generate clinical feedback strictly grounded in recorded session metrics and CIT-U Intramuscular Injection rubrics. The system shall enforce post-generation validation against numeric, aspiration, and terminology rules. If violations are detected, the system shall attempt regeneration once with specific violation notes, and fall back to a deterministic rule-based template if validation fails a second time. The original AI output shall be preserved immutably in `aiFeedbackText` (replacing legacy `selfFeedbackText`), with all instructor edits persisted separately in `instructorNote`. Evaluation plan: compare PRISM rubric decisions with instructor decisions (target >= 85%, pending adviser confirmation) and count instructor corrections per session.
- SDD impact (components added/changed, data design fields):
  - Added `lib/services/feedback_evidence.dart`: `FeedbackEvidence` model with allowed number bounds.
  - Added `lib/services/feedback_validator.dart`: `FeedbackValidator` static validation logic returning violation codes.
  - Added `lib/services/deterministic_feedback_builder.dart`: Deterministic fallback draft builder.
  - Updated `lib/services/feedback_service.dart`: PayloadBuilder cleaned; 2-pass generate-validate-regenerate loop with fallback.
  - Updated `lib/services/openrouter_api_client.dart`: System prompt rewritten, Llama 3.3 only, temp 0.3, mock feedback uses deterministic builder.
  - Updated `lib/models/session_model.dart`: Added `aiValidationStatus` and `aiValidationNotes`.
  - Updated `lib/services/feedback_release_service.dart`: Removed `aiFeedbackText` updates on single/batch release.
  - Updated `lib/screens/instructor/feedback_review_screen.dart`: Routed edits to `instructorNote`, added `ai_validation_badge`.
  - Updated `lib/screens/student/session_detail_screen.dart`: Shows `instructorNote` if non-empty, otherwise `aiFeedbackText`.
- Files changed:
  - `lib/services/feedback_evidence.dart`
  - `lib/services/feedback_validator.dart`
  - `lib/services/deterministic_feedback_builder.dart`
  - `lib/services/feedback_service.dart`
  - `lib/services/openrouter_api_client.dart`
  - `lib/models/session_model.dart`
  - `lib/services/feedback_release_service.dart`
  - `lib/screens/instructor/feedback_review_screen.dart`
  - `lib/screens/student/session_detail_screen.dart`
  - `test/feedback_validator_test.dart`
  - `test/feedback_prompt_test.dart`
  - `CHANGE_LOG.md`
- New/changed Firestore fields:
  - `sessions/{sessionId}.aiValidationStatus`: `String?` ("Passed" | "Auto-corrected" | "Template Fallback")
  - `sessions/{sessionId}.aiValidationNotes`: `List<String>?` (violation codes from first pass)
  - `sessions/{sessionId}.aiFeedbackText`: Immutable `String` (never modified after initial generation)
  - `sessions/{sessionId}.instructorNote`: `String` (contains instructor modifications and notes)
- Widget Keys added:
  - `Key('ai_validation_badge')`: Validation badge on `FeedbackReviewScreen` indicating pass, auto-corrected, or fallback status.
- Acceptance criteria (testable, pass/fail):
  - No generated feedback contains a number, timing or aspiration claim absent from the recorded metrics (validator-enforced).
  - `aiFeedbackText` is never modified after generation; instructor edits live in `instructorNote`.
  - Validation outcome is stored and visible to the instructor; template fallback is used after one failed regeneration.
  - Only Llama 3.3 is called.
  - SRS impact: UC-2.1 adds validation rules, regeneration/fallback, and the field name `aiFeedbackText` (fix `selfFeedbackText`). Evaluation plan: compare PRISM rubric decisions with instructor decisions (target >= 85%, pending adviser confirmation) and count instructor corrections per session.
- Suggested test cases (for STD / RTM):
  - TC-CR2-01: Validator rejects unrecorded numbers (e.g. 42.7) with `unsupported_number`.
  - TC-CR2-02: Validator rejects bleeding claims on a `noBleeding` session and safe claims on a `bleedingDetected` session (`aspiration_conflict`).
  - TC-CR2-03: Validator rejects timing words ("seconds", "duration") when aspiration duration is null/unrecorded (`unsupported_term`).
  - TC-CR2-04: Deterministic builder output passes all validator rules across all permutations of session outcomes.
  - TC-CR2-05: Payload builder omits duration and needle drift when unrecorded and excludes the "5-10s" claim.
  - TC-CR2-06: Instructor review edits write to `instructorNote` while preserving `aiFeedbackText` in Firestore.
  - TC-CR2-07: Validation badge displays green "Validated" for Passed, amber "Auto-corrected" for Auto-corrected, and amber "Template draft — review closely" for Template Fallback.
- Evidence to capture (screenshots/logs):
  - `FeedbackReviewScreen` displaying `Key('ai_validation_badge')` alongside editable AI draft and Undo/Revert controls.
  - Firestore document showing immutable `aiFeedbackText`, separate `instructorNote`, `aiValidationStatus`, and `aiValidationNotes`.
  - Unit test run logs showing all 25 tests passing in `test/feedback_validator_test.dart`, `test/feedback_prompt_test.dart`, and `test/aspiration_outcome_test.dart`.
- Known limitations:
  - LLM regeneration is limited to 1 retry to bound latency before defaulting to deterministic fallback draft.
  - Numeric validation allows +-0.05 tolerance to accommodate floating point rounding.

## CR-4 — CR-4 Firestore quarantine rules, secret hygiene and legacy cleanup
- Validation finding / Specific Objective:
  - Validation finding: The audit showed database rules did not enforce the Pre-Release Feedback Quarantine requirement (students could read unreleased AI feedback and base64 snapshots of pending/failed sessions, and could update their own session documents). Furthermore, `android/app/google-services.json` was tracked in git, and legacy MediaPipe/ML Kit files caused analyzer errors due to removed dependencies.
  - Specific Objective: Enforce Pre-Release Feedback Quarantine in Firestore rules, ensure repository secret hygiene, and eliminate analyzer errors by removing abandoned legacy code.
- Branch / PR:
  - Branch: `fix/security/rules_and_secret_hygiene`
- Summary of change:
  - Hardened `firestore.rules` to quarantine student session reads until `feedbackStatus == 'Released'`.
  - Restricted session update and delete permissions strictly to authenticated instructors (`role == 'Instructor'`), with a narrow exception allowing students to update only AI feedback fields on their own released practice sessions (`isPractice == true`).
  - Allowed student creation of sessions exclusively for self-practice sessions where `userId == auth.uid`, `isPractice == true`, and `feedbackStatus == 'Released'`.
  - Restricted `live_sessions/**` reads and writes to instructors only (protecting telemetry and WebRTC signaling).
  - Allowed instructors to query `users` by email and write release notifications to student notification subcollections.
  - Added root `firebase.json` declaring Firestore rules configuration.
  - Untracked `android/app/google-services.json` from git while preserving the local file, added `android/app/google-services.json.example`, and updated `.gitignore` for `google-services.json`, `*.jks`, `key.properties`, `.env`, `.env.json`, and `dist/`.
  - Removed obsolete leftover MediaPipe/ML Kit files (`hand_landmark_service.dart`, `pose_landmark_service.dart`, `angle_overlay_painter.dart`), achieving zero `flutter analyze` errors.
- Rules-vs-Calls Matrix:
  | Call Site | Operation | Caller | Allowed by Prior Rule? | Allowed by Hardened Rule? | Clinical & Security Rationale |
  |---|---|---|---|---|---|
  | `users/{uid}` | `get`, `set` | Student / Instructor | Yes (`auth.uid == uid`) | Yes (`auth.uid == uid`) | Auth profile creation and role lookup |
  | `users` (query by email) | `get` (`where email == x`) | Instructor | No (failed: only `auth.uid == uid`) | Yes (`isInstructor()`) | Resolves student email to UID upon feedback release |
  | `users/{uid}/notifications/{id}` | `list`, `get`, `update`, `delete` | Student / Instructor | Yes (`auth.uid == uid`) | Yes (`auth.uid == uid`) | Managing user's own in-app notification center |
  | `users/{targetUid}/notifications` | `add` (create) | Instructor | No (failed: only `auth.uid == targetUid`) | Yes (`isInstructor()`) | Instructor delivers feedback release alerts to student |
  | `sessions/{id}` | `create` (official RD) | Instructor | Yes (`auth != null`) | Yes (`isInstructor()`) | Saves completed or aborted clinical return-demonstration |
  | `sessions/{id}` | `create` (practice mode) | Student | Yes (`auth != null`) | Yes (`userId == auth.uid`, `isPractice == true`, `status == 'Released'`) | Student self-practice returns released feedback immediately |
  | `sessions` | `list` / query | Instructor | Yes (`isInstructor()`) | Yes (`isInstructor()`) | Instructor dashboard and section analytics |
  | `sessions/{id}` | `get` | Instructor | Yes (`isInstructor()`) | Yes (`isInstructor()`) | Session review and rubric grading screens |
  | `sessions/{id}` | `update` (draft / release) | Instructor | Yes (`isInstructor()`) | Yes (`isInstructor()`) | Feedback draft auto-save and single release |
  | `sessions` | `batch.update` | Instructor | Yes (`isInstructor()`) | Yes (`isInstructor()`) | Batch release by section, count, or IDs |
  | `sessions` | `list` / query | Student | Yes (read any own doc, even Pending) | Yes, only when `feedbackStatus == 'Released'` | Pre-Release Feedback Quarantine enforced |
  | `sessions/{id}` | `get` | Student | Yes (read any own doc, even Pending) | Yes, only when `feedbackStatus == 'Released'` | Direct doc lookup blocked until released |
  | `sessions/{id}` | `update` | Student | Yes (could edit own doc!) | Allowed ONLY for own practice sessions (`isPractice == true`, `status == 'Released'`) touching feedback keys | Tamper prevention: students cannot alter scores, angles, or official sessions |
  | `sessions/{id}` | `delete` | Any | No (`false`) | Instructors only | Instructors manage session lifecycle |
  | `live_sessions/{id}` | `set`, `snapshots`, `delete` | Instructor | Yes (`auth != null`) | Yes (`isInstructor()`) | Telemetry sync between camera and remote |
  | `live_sessions/{id}/ice_candidates` | `add`, `snapshots` | Instructor | Yes (`auth != null`) | Yes (`isInstructor()`) | WebRTC P2P signaling between instructor devices |
  | `instructor_roster/**` | `read`, `write` | Instructor | Yes (`auth.uid == instructorId`) | Yes (`auth.uid == instructorId && isInstructor()`) | Section and roster CSV management |
- How to deploy rules:
  1. Open the Firebase Console (`https://console.firebase.google.com/`).
  2. Select the PRISM project (`prism-app-ae2d6`).
  3. Navigate to **Firestore Database** -> **Rules** tab.
  4. Copy and paste the complete contents of `firestore.rules`.
  5. Click **Publish** to apply the security rules immediately.
- SRS impact (UC ids + new/changed requirement wording):
  - Pre-Release Feedback Quarantine: Students shall access session feedback, rubric scores, and session snapshots only after the supervising instructor explicitly reviews and releases the session (`feedbackStatus == 'Released'`). Prior to release, all session telemetry is quarantined and inaccessible to student accounts.
  - Session Document Integrity: Official session modification and deletion permissions are strictly restricted to authenticated instructors. Students may only populate AI feedback fields on their own released practice sessions.
- SDD impact (components added/changed, data design fields):
  - Added `firebase.json` project configuration file.
  - Updated `firestore.rules` with helper functions (`isSignedIn`, `isInstructor`), quarantine read/write conditions, and restricted practice update rule.
  - Added `isPractice: bool` field to `SessionModel` and set `isPractice: true` in `PracticeModeScreen`.
  - Added `android/app/google-services.json.example` template with sanitized credentials.
  - Updated `.gitignore` to ignore sensitive credentials, keystores, and environments.
  - Removed deprecated packages and legacy files `hand_landmark_service.dart`, `pose_landmark_service.dart`, and `angle_overlay_painter.dart`.
- Files changed:
  - `firestore.rules`
  - `firebase.json`
  - `.gitignore`
  - `android/app/google-services.json` (untracked)
  - `android/app/google-services.json.example` (created)
  - `lib/models/session_model.dart`
  - `lib/screens/student/practice_mode_screen.dart`
  - `lib/services/hand_landmark_service.dart` (deleted)
  - `lib/services/pose_landmark_service.dart` (deleted)
  - `lib/widgets/angle_overlay_painter.dart` (deleted)
  - `CHANGE_LOG.md`
- New/changed Firestore fields:
  - `sessions/{sessionId}.isPractice`: `bool` (indicates whether session is a self-practice session; defaults to false for official RDs).
- Widget Keys added:
  - None.
- Acceptance criteria (testable, pass/fail):
  - A student cannot read a Pending or Failed session by direct document lookup; can read it after release.
  - A student cannot update an official session or read `live_sessions`.
  - A student finishing self-practice successfully saves background AI feedback without permission errors.
  - Instructor flows (live demo, release, batch release, roster, notifications) and student practice mode work.
  - `git ls-files` shows no `google-services.json`, `.env`, `.jks` or `key.properties`.
  - `flutter analyze` reports zero errors.
  - Manual test (owner, after publishing the rules in the console): student A cannot open a Pending session; instructor releases it; student A can.
- Suggested test cases (for STD / RTM):
  - TC-CR4-01: Authenticated student attempts to read a session with `feedbackStatus: 'Pending'` via document get -> Firestore permission-denied.
  - TC-CR4-02: Authenticated student reads a session with `feedbackStatus: 'Released'` where `userId == auth.uid` -> Document read succeeds.
  - TC-CR4-03: Authenticated student attempts to update an official session document -> Firestore permission-denied.
  - TC-CR4-04: Authenticated student creates a practice session document with `isPractice: true`, `feedbackStatus: 'Released'` -> Create succeeds.
  - TC-CR4-05: Authenticated instructor reads any session (Pending or Released) -> Read succeeds.
  - TC-CR4-06: Authenticated instructor writes to `live_sessions/{instructorId}` -> Write succeeds.
  - TC-CR4-07: Authenticated student attempts to read/write `live_sessions/{instructorId}` -> Firestore permission-denied.
  - TC-CR4-08: Authenticated instructor adds release notification to student `users/{studentUid}/notifications` -> Write succeeds.
  - TC-CR4-09: Student finishes practice session -> AI background task successfully updates feedback fields (`aiFeedbackText`, `instructorNote`, `aiValidationStatus`, `aiValidationNotes`) on the practice document.
  - TC-CR4-10: Student attempts to modify score or angle fields on a practice session document -> Firestore permission-denied.
- Evidence to capture (screenshots/logs):
  - Firebase console rules simulator showing denied read for unreleased student session and allowed read for released session.
  - Terminal output of `git ls-files android/app/google-services.json` returning empty.
  - Terminal output of `flutter analyze` returning zero errors.
  - Terminal output of `flutter test` showing all unit tests passing.
- Known limitations:
  - Firestore security rules require manual publishing in Firebase Console or via Firebase CLI deploy.

## CR-2b — CR-2b Instructor edits AI feedback, private note, AI-failure fallback
- Validation finding / Specific Objective:
  - Validation finding: CR-2 misread the intended design by treating `aiFeedbackText` as immutable, routing instructor edits into `instructorNote`, and displaying `instructorNote` to students on session detail screens. This broke the intended flow where instructors edit the AI feedback draft before release to students, leaked the instructor's private clinical note to students, and left feedback empty when AI generation failed completely.
  - Specific Objective: Restore instructor editing of `aiFeedbackText` before release, preserve the untouched initial draft in `aiFeedbackOriginal`, ensure `instructorNote` remains strictly private to instructors, provide deterministic rule-based template fallback on complete AI generation failure, and prevent students from modifying `instructorNote` via Firestore rules.
- Branch / PR:
  - Branch: `fix/feedback/instructor_edit_and_private_note`
  - PR: `fix(feedback): restore instructor editing, keep note private, add ai failure fallback`
- Summary of change:
  - Added `aiFeedbackOriginal` to `SessionModel` (`fromFirestore`, `toFirestore`, `copyWith`) to retain the untouched initial AI draft permanently.
  - Updated `FeedbackService` to populate and save `aiFeedbackOriginal` alongside `aiFeedbackText` on both official and practice generation.
  - Updated single release in `FeedbackReleaseService.releaseSession` to persist edited `aiFeedbackText` and `instructorNote` while never modifying `aiFeedbackOriginal`.
  - Updated `FeedbackReviewScreen` to edit `aiFeedbackText` in the draft box and private notes in `instructorNote` (relabeled "Private instructor note (not shown to students)"); updated Revert button to restore `aiFeedbackOriginal`; enabled draft auto-saving of both fields via `InstructorSessionRepository.updateFeedbackDraft`.
  - Removed all displays of `instructorNote` from student-facing screens; updated `SessionDetailScreen` to show only `aiFeedbackText` labeled "AI-assisted feedback, reviewed by your instructor" for official sessions and "AI guide for practice, not reviewed by an instructor" (or fallback notice) for practice sessions via `FeedbackLabels`.
  - Hardened `firestore.rules` to disallow student writes to `instructorNote` on practice sessions, allowing only `['aiFeedbackText', 'aiFeedbackOriginal', 'aiValidationStatus', 'aiValidationNotes']`.
  - Added deterministic fallback on AI generation failure (timeout, network, API error, empty reply) in `FeedbackService`: populates `DeterministicFeedbackBuilder` output into `aiFeedbackText` and `aiFeedbackOriginal` with `aiValidationStatus = 'Template Fallback'` and `aiValidationNotes = ['ai_unavailable']`; official sessions retain `feedbackStatus = 'Feedback Generation Failed'` for instructor review and editing while practice sessions remain `Released`.
  - Added amber banner on `FeedbackReviewScreen` informing the instructor when AI generation failed and a template summary is shown.
  - Surgically updated `AGENTS.md` and `FRONTEND.md` to eliminate outdated immutability guidance and document accurate feedback editing semantics.
  - Added unit test suite in `test/feedback_service_test.dart` verifying fallback behavior and label generation across official and practice sessions.
- SRS impact (UC ids + new/changed requirement wording):
  - UC-4.2 step 4: The instructor may review and edit the AI-generated feedback draft before releasing it to the student. The edited text is persisted in `aiFeedbackText` and delivered to the student upon release. The original AI-generated draft is retained immutably in `aiFeedbackOriginal` for audit and quality tracking. The instructor note (`instructorNote`) is strictly private to the instructor and is never released or displayed to students.
- SDD impact (components added/changed, data design fields):
  - Updated `SessionModel`: added `aiFeedbackOriginal: String` (with safe fallback to `aiFeedbackText`).
  - Updated `FeedbackService`: accepts optional injected `OpenRouterApiClient`, populates `aiFeedbackOriginal`, implements fallback on failure, and exposes `FeedbackLabels.studentFeedbackLabel`.
  - Updated `FeedbackReleaseService`: writes `aiFeedbackText` and `instructorNote` upon release; does not touch `aiFeedbackOriginal`.
  - Updated `InstructorSessionRepository`: `updateFeedbackDraft` supports updating `instructorNote` and `aiFeedbackText`.
  - Updated `FeedbackReviewScreen`: draft edits `aiFeedbackText`, note edits `instructorNote`, Revert restores `aiFeedbackOriginal`, amber banner shown on fallback.
  - Updated `SessionDetailScreen`: displays `aiFeedbackText` with role-specific labels; never shows `instructorNote`.
  - Updated `firestore.rules`: student practice update field whitelist changed to `['aiFeedbackText', 'aiFeedbackOriginal', 'aiValidationStatus', 'aiValidationNotes']`.
- Files changed:
  - `lib/models/session_model.dart`
  - `lib/services/feedback_service.dart`
  - `lib/services/feedback_release_service.dart`
  - `lib/services/instructor_session_repository.dart`
  - `lib/screens/instructor/feedback_review_screen.dart`
  - `lib/screens/student/session_detail_screen.dart`
  - `lib/screens/student/practice_mode_screen.dart`
  - `firestore.rules`
  - `AGENTS.md`
  - `FRONTEND.md`
  - `test/feedback_service_test.dart`
  - `CHANGE_LOG.md`
- New/changed Firestore fields:
  - `sessions/{sessionId}.aiFeedbackText`: `String` (feedback text shown to students; editable by instructor before release)
  - `sessions/{sessionId}.aiFeedbackOriginal`: `String` (untouched initial AI draft, written once at generation, never changed)
  - `sessions/{sessionId}.instructorNote`: `String` (private instructor note about the student; never displayed to students)
- Widget Keys added:
  - None (preserved all existing keys: `ai_feedback_field`, `instructor_note_field`, `release_button`, `ai_validation_badge`).
- Acceptance criteria (testable, pass/fail):
  - Instructor edits the AI text, releases, and the student sees the edited text; `aiFeedbackOriginal` still holds the original draft.
  - The private instructor note appears in no student screen.
  - If AI generation fails completely, a rule-based summary from the recorded metrics is stored and shown (instructor sees a banner; practice student sees an "Automatic summary" label); feedback is never empty.
  - `AGENTS.md` and `FRONTEND.md` no longer say `aiFeedbackText` is immutable.
  - Practice feedback is shown as an AI guide and cannot be edited by the student; a student cannot write `instructorNote` (rules).
  - SRS impact: UC-4.2 step 4: the instructor may edit the AI-generated feedback draft; the original draft is retained; the instructor note is private and not released. SDD: fields `aiFeedbackText`, `aiFeedbackOriginal`, `instructorNote`.
- Suggested test cases (for STD / RTM):
  - TC-CR2B-01: Instructor edits AI draft on `FeedbackReviewScreen` and releases session -> `sessions/{id}.aiFeedbackText` contains edited text, `sessions/{id}.aiFeedbackOriginal` retains original draft, student sees edited text labeled "AI-assisted feedback, reviewed by your instructor".
  - TC-CR2B-02: Instructor adds text to "Private instructor note" and releases -> `sessions/{id}.instructorNote` holds private note, student session detail screen does not display note anywhere.
  - TC-CR2B-03: Instructor edits draft and clicks "Revert" -> `_aiFeedbackController` restores `aiFeedbackOriginal`.
  - TC-CR2B-04: AI generation times out or returns API error -> session stores deterministic template summary in `aiFeedbackText` and `aiFeedbackOriginal` with `aiValidationStatus = 'Template Fallback'`, `aiValidationNotes = ['ai_unavailable']`; instructor sees amber banner on review screen; practice student sees "Automatic summary from your recorded metrics (AI unavailable). Not reviewed by an instructor."
  - TC-CR2B-05: Authenticated student attempts to update `instructorNote` on their own practice session -> Firestore rules reject update.
- Evidence to capture (screenshots/logs):
  - `FeedbackReviewScreen` showing edited draft and separate "Private instructor note (not shown to students)" field.
  - `SessionDetailScreen` showing edited feedback with "AI-assisted feedback, reviewed by your instructor" banner and no private note.
  - `FeedbackReviewScreen` showing amber fallback banner for session where AI was unavailable.
  - Terminal test runner output showing 30 passing tests including `test/feedback_service_test.dart`.
- Known limitations:
  - The private note is hidden in the app UI but, being in the session document, is readable by a student who queries Firestore directly. A separate instructor-only collection would remove that.


