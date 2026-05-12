# PRISM: Parenteral Return-demonstration Injection Skills Monitor

[cite_start]**PRISM** is an AI-driven Android application designed for the **Cebu Institute of Technology – University (CIT-U)** Nursing Department[cite: 38]. [cite_start]It utilizes **MediaPipe** computer vision and the **Llama 3.3** LLM to evaluate safety-critical procedural components of parenteral injection return demonstrations[cite: 38].

## 🚀 Key Features
* [cite_start]**Real-time Angle Detection**: Monitors needle insertion and withdrawal angles using Landmarks 0 (wrist) and 8 (index tip)[cite: 42, 49].
* [cite_start]**Aspiration Verification**: Tracks Landmark 4 (thumb tip) displacement to confirm proper plunger withdrawal technique[cite: 49, 137].
* [cite_start]**AI Clinical Feedback**: Generates structured, clinically worded performance commentary via **Llama 3.3** (OpenRouter API)[cite: 43, 65].
* [cite_start]**Role-Based Access**: Specialized interfaces for **Nursing Students** and **Clinical Instructors** powered by Firebase[cite: 44, 161].
* [cite_start]**Instructor Review Loop**: Instructors validate AI-generated feedback before it is released to students[cite: 70, 192].

## 🏗️ Architecture
[cite_start]The project utilizes a **Feature-Based Layered Architecture** to maintain modularity and support real-time performance[cite: 122, 123].

* [cite_start]`lib/features/detection`: Module 1 — Real-time computer vision and geometric analysis[cite: 124].
* [cite_start]`lib/features/feedback_engine`: Module 2 — AI processing and clinical guidance generation[cite: 148].
* [cite_start]`lib/features/auth`: Module 3 — Firebase Authentication and role claims[cite: 158].
* [cite_start]`lib/features/student_view` & `lib/features/instructor_view`: Module 4 — Dashboards and record review[cite: 182].

## 🛠️ Technical Specifications
* [cite_start]**Platform**: Android 8.0 (API Level 26) or higher[cite: 81].
* [cite_start]**Minimum Hardware**: 3 GB RAM, 8 MP rear camera with autofocus[cite: 82, 103].
* [cite_start]**Accuracy Target**: Mean Absolute Error (MAE) $\le 3^{\circ}$ for angle detection[cite: 49, 202].
* [cite_start]**Frontend/Backend**: Flutter (Frontend/UI) integrated with Firebase Firestore and OpenRouter API[cite: 38, 115].

## 💉 Injection Standards (CIT-U Rubric)
[cite_start]PRISM evaluates four parenteral injection types[cite: 42]:
| Injection Type | Target Angle | Landmark Reference |
| :--- | :--- | :--- |
| **Intramuscular (IM)** | $90^{\circ}$ | [cite_start]L0 to L8 Vector [cite: 49] |
| **Subcutaneous (SubQ)** | $45^{\circ}$ | [cite_start]L0 to L8 Vector [cite: 49] |
| **Intravenous (IV)** | $15^{\circ}$ | [cite_start]L0 to L8 Vector [cite: 49] |
| **Intradermal (ID)** | $10^{\circ}$ | [cite_start]L0 to L8 Vector [cite: 49] |

## ⚠️ Constraints & Safety
* [cite_start]**Advisory Feedback**: AI-generated feedback is advisory and does not replace instructor judgment[cite: 47, 90].
* [cite_start]**Privacy**: No session video footage is stored; only computed metrics and text feedback are persisted[cite: 89, 216].
* [cite_start]**Hardware Note**: Due to real-time inference requirements, testing on a physical Android device is highly recommended over emulators[cite: 104, 106].