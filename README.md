# PRISM: Parenteral Return-demonstration Injection Skills Monitor

**PRISM** is an AI-driven Android application designed for the **Cebu Institute of Technology – University (CIT-U)** Nursing Department. It utilizes custom computer vision models and the **Llama 3.3** LLM to evaluate safety-critical procedural components of Intramuscular (IM) injection return demonstrations.

## 🚀 Key Features
* **Real-time Angle Detection**: Monitors needle insertion and withdrawal angles using custom ML integration.
* **Aspiration Verification**: Tracks plunger displacement to confirm proper withdrawal technique.
* **AI Clinical Feedback**: Generates structured, clinically worded performance commentary via **Llama 3.3** (OpenRouter API).
* **Role-Based Access**: Specialized interfaces for **Nursing Students** and **Clinical Instructors** powered by Firebase.
* **Instructor Review Loop**: Instructors validate AI-generated feedback before it is released to students.

## 🏗️ Architecture
The project utilizes a **Feature-Based Layered Architecture** to maintain modularity and support real-time performance.

* `lib/features/detection`: Module 1 — Real-time computer vision and geometric analysis.
* `lib/features/feedback_engine`: Module 2 — AI processing and clinical guidance generation.
* `lib/features/auth`: Module 3 — Firebase Authentication and role claims.
* `lib/features/student_view` & `lib/features/instructor_view`: Module 4 — Dashboards and record review.

## 🛠️ Technical Specifications
* **Platform**: Android 8.0 (API Level 26) or higher.
* **Minimum Hardware**: 3 GB RAM, 8 MP rear camera with autofocus.
* **Accuracy Target**: Mean Absolute Error (MAE) $\le 3^{\circ}$ for angle detection.
* **Frontend/Backend**: Flutter (Frontend/UI) integrated with Firebase Firestore and OpenRouter API.

## 💉 Injection Standards (CIT-U Rubric)
PRISM evaluates Intramuscular (IM) injection technique:
| Injection Type | Target Angle |
| :--- | :--- |
| **Intramuscular (IM)** | $90^{\circ}$ |

## ⚠️ Constraints & Safety
* **Advisory Feedback**: AI-generated feedback is advisory and does not replace instructor judgment.
* **Privacy**: No session video footage is stored; only computed metrics and text feedback are persisted.
* **Hardware Note**: Due to real-time inference requirements, testing on a physical Android device is highly recommended over emulators.