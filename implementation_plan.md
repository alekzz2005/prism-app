# Aspiration Enhancements & AI Feedback Wiring

This plan addresses your recent requests: fixing the 2-hand aspiration sensitivity, adding live metric displays during aspiration, gracefully handling camera disconnections, adding the "Detection Lost" overlay, and fully wiring up the OpenRouter Llama 3.3 AI feedback generation from your flowcharts.

## User Review Required

> [!WARNING]
> **OpenRouter AI Generation Time**
> Generating AI feedback via OpenRouter takes a few seconds. I will add a loading screen to the Remote Control when you tap "Complete & Save Session" so it can wait for the AI's response before fully closing the session.

## Open Questions

> [!IMPORTANT]
> 1. **FCM Notifications:** You mentioned implementing the Firebase Cloud Messaging push notification when feedback is released. Flutter usually requires a backend (like Firebase Cloud Functions) to securely send FCM messages to devices. Should I mock this out with a standard Flutter `print()` / comment for now, or do you have a Cloud Function already deployed that I should call?

## Proposed Changes

---

### 1. Aspiration Sensitivity Fix

#### [MODIFY] [aspiration_detection_service.dart](file:///d:/GitHub%20Repositories/prism-app/lib/services/aspiration_detection_service.dart)
- Introduce a separate `_twoHandDisplacementThreshold` (e.g. 0.06 instead of 0.025) because the distance between two separate wrists naturally fluctuates much more than the distance between fingers on the same hand.

---

### 2. Live Aspiration Metrics

#### [MODIFY] [live_session_service.dart](file:///d:/GitHub%20Repositories/prism-app/lib/services/live_session_service.dart)
- Update `LiveSessionModel` to include `liveAspirationResult` and `liveAspirationDuration`.
- Add a new method `updateLiveAspiration()` to push these metrics at 2Hz.

#### [MODIFY] [camera_node_screen.dart](file:///d:/GitHub%20Repositories/prism-app/lib/screens/instructor/camera_node_screen.dart)
- During the 2Hz `_syncLiveAngle` timer, if the phase is `aspiration`, push the live aspiration result and duration to Firestore.

#### [MODIFY] [remote_control_screen.dart](file:///d:/GitHub%20Repositories/prism-app/lib/screens/instructor/remote_control_screen.dart)
- Update the UI during the `aspiration` phase to show these live numbers streaming in real-time, replacing the generic "Aspiration Tracking Active" text.

---

### 3. Camera Disconnect & Detection Lost

#### [MODIFY] [camera_node_screen.dart](file:///d:/GitHub%20Repositories/prism-app/lib/screens/instructor/camera_node_screen.dart)
- **Disconnect:** Add logic to the `dispose()` method to immediately set `cameraNodeActive = false` in Firestore so the Remote Control doesn't get stuck if you exit the camera.
- **Detection Lost:** Render a "Detection Lost - Please Readjust" semi-transparent red overlay on top of the camera preview when `_hands.isEmpty` to match your flowchart.

---

### 4. AI Feedback Generation (Flowchart 2)

#### [MODIFY] [feedback_service.dart](file:///d:/GitHub%20Repositories/prism-app/lib/services/feedback_service.dart)
- Refactor `PayloadBuilder.buildPrompt` to accept a `SessionModel` instead of `SessionStateProvider` (since the live session architecture uses `SessionModel`).

#### [MODIFY] [remote_control_screen.dart](file:///d:/GitHub%20Repositories/prism-app/lib/screens/instructor/remote_control_screen.dart)
- When "Complete & Save Session" is tapped, display a loading indicator.
- Pass the finalized `SessionModel` to `FeedbackService`, fetch the OpenRouter Llama 3.3 response, append it to `aiFeedbackText`, and then save to Firestore.

---

### 5. Feedback Release FCM (Flowchart 3)

#### [MODIFY] [feedback_release_service.dart](file:///d:/GitHub%20Repositories/prism-app/lib/services/feedback_release_service.dart)
- Add the hook to send a push notification (or log it) right after `feedbackStatus` is set to `"Released"`.

## Verification Plan

### Manual Verification
1. Run Remote Control and Camera Node.
2. Verify holding the syringe with two hands does not immediately trigger "Correct" until actually pulled.
3. Verify live numbers appear on the Remote Control during aspiration.
4. Close the Camera Node and verify the Remote Control correctly identifies the camera is gone.
5. Obscure the camera and verify "Detection Lost" appears.
6. Complete a session and verify OpenRouter is queried (AI Draft appears in the Review Screen).
