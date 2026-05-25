# Implementation Plan: Roboflow Computer Vision Integration for IM Injection

This plan outlines the integration of the **Roboflow Rapid Workflows API** into PRISM to evaluate intramuscular (IM) return-demonstrations in real-time. 

For IM injections, PRISM will bypass the standard MediaPipe hand-tracking algorithm and instead capture, compress, and stream camera frames to Roboflow at 2Hz, calculate the acute relative angle between the syringe and arm vectors, score the angle on a CIT-U 1-5 scale, and synchronise the metrics with Firestore. For all other injection types (`SubQ`, `IV`, `ID`), the app will fall back automatically to the existing MediaPipe Hand Landmarker.

---

## User Review Required

> [!IMPORTANT]
> **Dependency Addition (`image` package)**
> Dart lacks built-in image compression (JPEG encoding) APIs. To convert `CameraImage` (YUV420) frames to the base64-encoded JPEGs required by the Roboflow API, we need to add the `image` package dependency to `pubspec.yaml`. 
>
> **Roboflow API Key Config**
> We will configure the Roboflow API key via `--dart-define=ROBOFLOW_API_KEY=your_key` or hardcoded fallback. To allow robust testing without an active API key, we will implement an **in-app simulation/mock mode** for Roboflow (similar to OpenRouter's mock mode) that generates valid coordinates and angles when no API key is set or when simulated.

---

## Proposed Changes

### 1. Dependency Update

#### [MODIFY] [pubspec.yaml](file:///c:/Users/User/Desktop/prism-app/pubspec.yaml)
- Add the `image: ^4.2.0` package under `dependencies` to provide YUV-to-JPEG conversion and compression tools.

---

### 2. Roboflow Integration Service

#### [NEW] [roboflow_service.dart](file:///c:/Users/User/Desktop/prism-app/lib/services/roboflow_service.dart)
Create a standalone `RoboflowDetectionService` to handle the endpoint request, image processing, vector math, and scoring:
- **JPEG Encoder**: High-performance pure-Dart YUV420 to RGB to JPEG compressor. By only executing this once every 500ms (2Hz), it will consume negligible CPU (<15ms per run), keeping the UI completely stutter-free.
- **API Request**: Send POST requests to `https://detect.roboflow.com/infer/workflows/veincarmell-pangilinan-cit-edu/find-syringe-arm-and-needle` with base64 payload.
- **Robust JSON Parser**: Check multiple possible JSON structures in the workflow response (`outputs`, step-based outputs, or root keys) to ensure it is resilient to workflow changes.
- **Angle Vector Math**: 
  - Dynamic arm direction: If arm bounding box `width > height`, the arm is horizontal `V_a = (1, 0)`. Else, the arm is vertical `V_a = (0, 1)`.
  - Syringe direction: If a `needle` is detected, the syringe vector `V_s` runs from the syringe center to the needle center. Else, it falls back to the vector from the syringe center to the arm center (the direction of insertion).
  - Relative acute angle calculation:
    $$\cos(\theta) = \frac{|V_s \cdot V_a|}{|V_s| \times |V_a|}$$
    $$\theta = \arccos(\cos(\theta)) \times \frac{180}{\pi}$$
    This provides an mathematically precise, acute relative angle in the `[0°, 90°]` range.
- **Rubric Scoring**: Implement the IM-specific scoring rubric (90° target, ±5° tolerance):
  - **5/5**: within ±1° (89° to 91°)
  - **4/5**: within ±2° (88° to 92°)
  - **3/5**: within ±3° (87° to 93°)
  - **2/5**: within ±5° (85° to 95°)
  - **1/5**: beyond ±5° (<85° or >95°)
- **Mock Mode**: Auto-generate high-accuracy simulated coordinates when no key is set or when simulated, enabling comprehensive pipeline testing without server limits.

---

### 3. Camera Node Integration

#### [MODIFY] [camera_node_screen.dart](file:///c:/Users/User/Desktop/prism-app/lib/screens/instructor/camera_node_screen.dart)
- **Role Routing / Fallback**:
  - Check the active session's `injectionType` inside `_currentSession`.
  - If `injectionType == 'IM'`:
    - Disable on-device MediaPipe hand landmarker processing in `_onFrame` to save CPU resources.
    - Cache the latest `CameraImage` frame to `_latestFrame`.
    - In the 2Hz periodic timer `_syncMetrics()`, pass `_latestFrame` to `RoboflowDetectionService.detectAngle()`.
    - Handle results:
      - If syringe/arm is not found: set `detectionLost = true` in Firestore, flash the "Detection Lost" red warning overlay.
      - If found: set `detectionLost = false`, calculate relative angle, update `_liveAngle`, and push `_liveAngle` to Firestore at 2Hz.
  - If `injectionType != 'IM'` (`SubQ`, `IV`, `ID`):
    - Fall back completely to the original MediaPipe `HandLandmarkService` pipeline, ensuring all other modules function identically.
- **Phase Handlers**:
  - Update `_scoreAngle` or utilize the service's `scoreIMAngle` specifically when the phase moves to `insertion_locked` or `withdrawal_locked` for IM injection.

---

## Verification Plan

### Automated Build Verification
- Add a new unit test `test/roboflow_service_test.dart` to verify:
  1. The vector math angle calculation for horizontal and vertical arms.
  2. The custom CIT-U 1-5 IM scoring logic.
  3. The robust JSON response parser with multiple payload shapes.

### Manual Verification
1. Open the Camera Node screen in **IM Injection** mode.
2. Verify that in **Mock Mode**, a simulated syringe angle is successfully generated, synced to Firestore at 2Hz, and displayed dynamically.
3. Obscure the camera (or simulate no objects found) and verify the "Detection Lost" screen appears and Firestore is updated with `detectionLost: true`.
4. Trigger phase changes from the Remote Control (`insertion` -> `insertion_locked` -> `aspiration` -> `withdrawal` -> `withdrawal_locked`) and verify the IM-specific scoring rubric is correctly computed and saved in Firestore.
