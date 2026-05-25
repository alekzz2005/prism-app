# PRISM Project Architecture

## Overview
PRISM (Parenteral Return-demonstration Injection Skills Monitor) is an AI-powered Flutter application designed for evaluating nursing student return-demonstrations. It leverages computer vision via MediaPipe for real-time tracking of injection angles (insertion/withdrawal) and aspiration, processes the metrics using Llama 3.3 for clinical AI feedback, and synchronizes live data between a tracking device and a remote control device via Firebase Firestore.

The application uses standard Flutter architecture patterns with `Provider` for state management. The codebase is organized into distinct domain layers for clarity and separation of concerns.

## Directory Structure and Components

### `lib/core/`
Contains core application configurations and constants.
*   **`injection_config.dart`**: Defines the `InjectionConfig` model and `InjectionConfigService`. This holds the target angles and tolerances for the four main injection types (IM: 90°, SubQ: 45°, IV: 15°, ID: 10°).

### `lib/models/`
Defines data structures that map directly to the backend schema (Firestore).
*   **`session_model.dart`**: Contains `SessionModel`, representing a completed student injection session, including component scores, angles, feedback text, status, and instructor notes.

### `lib/providers/`
Manages application state using `ChangeNotifier` for reactive UI updates across the widget tree.
*   **`session_state_provider.dart`**: Manages the current live session state (e.g., active phase, angles, component scores, current target type) during a live return demonstration.
*   **`user_role_provider.dart`**: Handles fetching and exposing the current authenticated user's role (Student vs. Instructor).

### `lib/services/`
Handles business logic, API communication, computer vision processing, and database interactions.
*   **`auth_service.dart`**: Wrapper for Firebase Authentication.
*   **`detection_service.dart`**: Main orchestrator for computer vision logic and angle computation utilities.
*   **`hand_landmark_service.dart` / `pose_landmark_service.dart`**: Interfaces with Google ML Kit/MediaPipe to extract body and hand node coordinates from the live camera stream.
*   **`aspiration_detection_service.dart`**: Analyzes plunger displacement tracking to evaluate the student's aspiration technique.
*   **`withdrawal_detection_service.dart`**: Evaluates the angle and smoothness of needle withdrawal relative to the insertion path.
*   **`feedback_service.dart` / `feedback_release_service.dart`**: Manages generating and saving AI feedback, including constructing contextual payloads for the LLM. Handles the logic for releasing feedback to students.
*   **`openrouter_api_client.dart`**: Handles HTTP requests to the OpenRouter API to fetch feedback from the `llama-3.3-70b-instruct` model.
*   **`roster_service.dart`**: Parses CSV files for class roster setups and matches registered students to instructor sessions.
*   **`live_session_service.dart`**: Syncs real-time telemetry (angles, phases) between the tracking device (Tripod) and the instructor's device (Desk) via a high-frequency Firestore stream.
*   **`instructor_session_repository.dart`**: Manages specialized Firestore queries for instructor dashboard views.
*   **`feedback_exceptions.dart`**: Custom error classes handling failures during AI response generation.

### `lib/screens/`
Contains the UI layers separated by user flow and roles.
*   **`auth/`**
    *   **`login_screen.dart` / `register_screen.dart`**: Firebase email/password authentication flows.
*   **`instructor/`**
    *   **`instructor_dashboard_screen.dart`**: Main entry point for instructors to select their operational mode (Setup, Remote Control, Camera Node).
    *   **`live_demo_setup_screen.dart`**: Interface for loading CSV rosters and configuring the live class environment.
    *   **`remote_control_screen.dart`**: The instructor's desk view to monitor live angles and manually transition session phases (waiting → insertion → aspiration → withdrawal).
    *   **`camera_node_screen.dart`**: The tripod device view that processes the camera feed via MediaPipe and streams telemetry to Firestore.
    *   **`feedback_review_screen.dart`**: Allows instructors to review the Llama 3.3 output, append manual notes, and officially release the session feedback to the student.
*   **`student/`**
    *   **`my_sessions_screen.dart`**: Tabbed student dashboard listing completed sessions filtered by injection type.
    *   **`session_detail_screen.dart`**: Detailed view of a single released session, displaying scores, detected angles, and the AI/Instructor feedback.
    *   **`injection_type_screen.dart` / `detection_screen.dart` / `session_complete_screen.dart`**: Flows related to student-side practice and immediate post-session states.
*   **`shared/`**
    *   **`profile_screen.dart`**: Shared user profile management.

### `lib/widgets/`
Reusable UI components.
*   **`auth_wrapper.dart`**: The root routing widget that listens to `FirebaseAuth.instance.authStateChanges()` and seamlessly directs users to either Login, Student Dashboard, or Instructor Dashboard.
*   **`angle_overlay_painter.dart`**: A `CustomPainter` that draws the computed syringe vector overlay directly onto the live camera preview.
*   **`angle_badge.dart`**: A UI pill badge component used to display real-time angle metrics clearly.

## Core Architectural Workflows

1.  **Dual-Device Syncing**: The system is designed for a two-device setup. The **Camera Node** acts strictly as a sensor, performing on-device ML inference and pushing to `live_sessions/{instructorId}`. The **Remote Control** listens to this node and acts as the state controller, managing the session's lifecycle without needing to process heavy ML tasks.
2.  **Immutable AI Feedback**: Once a session completes, the system constructs a metric payload and requests feedback from Llama 3.3. This response is saved to Firestore as `aiFeedbackText` and is strictly immutable. Instructors can append to `instructorNote`, but the raw AI evaluation is preserved for data integrity.
3.  **Role-Based Access & Routing**: Firebase rules enforce that students can only read sessions where `feedbackStatus == "Released"`. At the application level, `AuthWrapper` prevents route bleeding between Student and Instructor views.
