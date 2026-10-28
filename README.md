# PRISM: Parenteral Return-demonstration Injection Skills Monitor

**PRISM** is an AI-driven Android application designed for the **Cebu Institute of Technology – University (CIT-U)** Nursing Department. It utilizes custom computer vision models (via Roboflow API) and the **Llama 3.3** LLM to evaluate safety-critical procedural components of Intramuscular (IM) injection return demonstrations.

## 🚀 Key Features
* **Real-time Angle Detection**: Monitors syringe insertion angles dynamically using a custom YOLOv8 model via the Roboflow Workflow API.
* **Aspiration Verification**: Tracks plunger displacement to confirm proper withdrawal technique.
* **AI Clinical Feedback**: Generates structured, clinically worded performance commentary via **Llama 3.3** (OpenRouter API).
* **Role-Based Access**: Specialized interfaces for **Nursing Students** and **Clinical Instructors** powered by Firebase.
* **Instructor Review Loop**: Instructors validate AI-generated feedback before it is released to students.

## 🏗️ Architecture
The project utilizes a **Service-Oriented Architecture** to maintain modularity and support real-time performance.

* `lib/services/`: Core logic modules (e.g., `roboflow_service.dart` for CV, `openrouter_api_client.dart` for LLM).
* `lib/screens/`: Role-based views categorized into `/auth`, `/instructor`, and `/student`.
* `lib/providers/`: Global state management for live session tracking.
* `lib/models/`: Firebase data models and detection payloads.

## 🛠️ Technical Specifications
* **Platform**: Android 8.0 (API Level 26) or higher.
* **Minimum Hardware**: 3 GB RAM, 8 MP rear camera with autofocus.
* **Accuracy Target**: Angle estimation utilizing Bounding Box Aspect Ratio triangulation.
* **Frontend/Backend**: Flutter (Frontend/UI) integrated with Firebase Firestore and OpenRouter API.
* **Computer Vision**: Hosted Roboflow YOLOv8 Object Detection pipeline.

## 💉 Injection Standards (CIT-U Rubric)
PRISM evaluates Intramuscular (IM) injection technique:
| Injection Type | Target Angle |
| :--- | :--- |
| **Intramuscular (IM)** | $90^{\circ}$ |

## 🚀 Setup & Running

PRISM uses compile-time environment injection via `--dart-define-from-file` to keep API credentials secure and decoupled from compiled binaries.

### 1. Environment Configuration
Copy `.env.json.example` to `.env.json` in the project root:
```bash
cp .env.json.example .env.json
```
Populate `.env.json` with your credentials:
```json
{
  "OPENROUTER_API_KEY": "your-openrouter-key",
  "ROBOFLOW_API_KEY": "your-roboflow-key",
  "ROBOFLOW_WORKFLOW_URL": "your-roboflow-workflow-url"
}
```

### 2. Running the App
Run using the shortcut script:
```powershell
.\run
```
Or directly with Flutter:
```bash
flutter run --dart-define-from-file=.env.json
```

> [!IMPORTANT]
> Running with plain `flutter run` without `--dart-define-from-file=.env.json` leaves credentials empty, causing live Roboflow CV detection to fail. Always run with `.\run` or `--dart-define-from-file=.env.json`.

For release APK generation and deployment instructions, refer to [DEPLOYMENT.md](DEPLOYMENT.md).

## ⚠️ Constraints & Safety
* **Advisory Feedback**: AI-generated feedback is advisory and does not replace instructor judgment.
* **Privacy**: No session video footage is stored; only computed metrics and text feedback are persisted.
* **Network Requirement**: Fast internet connection is recommended to minimize latency during live Roboflow API camera tracking.