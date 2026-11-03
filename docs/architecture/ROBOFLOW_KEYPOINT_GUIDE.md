# PRISM App: Roboflow Keypoint Detection Guide

This document serves as a comprehensive reference for AI agents and developers working on the PRISM app. It explains how the computer vision model was migrated to Keypoint Detection, how to correctly annotate data, and how the vector math works.

## 1. The Shift to Keypoint Detection
Initially, PRISM used standard Object Detection (bounding boxes). However, computing the exact 90-degree angle of an Intramuscular (IM) injection using the center of bounding boxes proved inaccurate. 

The app now uses **Keypoint Detection**. By training the AI to locate 5 specific microscopic dots (keypoints) on the arm and syringe, the Flutter app can draw perfect geometric lines and calculate the relative angle using high-precision vector algebra.

---

## 2. The 5 Keypoints Architecture
The Roboflow dataset is divided into two classes, containing a total of 5 keypoints.

### Class 1: `syringe` (3 Keypoints)
1. `plunger_top`
2. `barrel_base`
3. `needle_tip`

### Class 2: `arm` (2 Keypoints)
1. `arm_top` (near the shoulder)
2. `arm_bottom` (near the elbow)

---

## 3. The "Golden Rules" of Annotation
To ensure the AI trains correctly and the math remains accurate, annotators must follow these strict rules:

### A. The Golden Rule of Camera Angles
* **Rule:** Training photos must look exactly like what the tripod camera will see during the live clinical exam.
* **Avoid:** Full-body shots, runway models, or pictures taken from across the room.
* **Ideal:** Tight, zoomed-in shots where the arm takes up most of the vertical frame and the syringe enters from the side. Front and back views of the arm are both perfectly fine, as long as the zoom level matches the tripod.

### B. Syringe Annotation
* **Perfectly Straight Line:** The 3 syringe dots must form a perfectly straight line down the center axis of the barrel.
* **Occlusion (Hidden Parts):** It is 100% correct to **assume/estimate** where the `plunger_top` is if the nursing student's hand is covering it. Place the dot over the glove where it logically exists. This teaches the AI "object permanence."
* **Needle Tip Insertion:** When the needle is inserted, do **NOT** try to guess where the metal tip is deep inside the muscle. Place the `needle_tip` dot exactly where the blue plastic hub touches the surface of the skin. Because the syringe is a rigid line, the math remains perfectly accurate, and the AI can easily see the hub.

### C. Arm Annotation
* **Hug the Skin Edge:** The black line connecting `arm_top` and `arm_bottom` should trace the **surface edge** of the skin where the needle is entering. Do not draw it down the bone/center of the arm. This ensures the math calculates the 90-degree angle relative to the exact skin slope the nurse is aiming at.
* **Anatomical Anchors Only:** `arm_top` must be near the shoulder, and `arm_bottom` near the elbow. **Never** place the `arm_top` dot at the injection site. The AI must be able to recognize the arm even when the syringe is completely missing from the camera view.
* **Ignore Bumps/Lumps:** Keep the line long (from shoulder to elbow). If the patient's arm is bumpy, let the straight line cut slightly through the lumps. The goal is to capture the *overall general slant* of the arm.

---

## 4. Addressing "Jitter" in the Flutter Code
Because the AI is forced to "guess" where the `plunger_top` is when it is covered by a hand, that specific keypoint will naturally jitter and jump around by a few pixels from frame to frame.

* **The Problem:** If the app relies on the distance between `plunger_top` and `barrel_base` to detect aspiration (pulling back the plunger), this jitter will cause false aspirations.
* **The Code Solution:** The Flutter app (`detection_service.dart`) uses a **Gaussian Smoothing Buffer**. Instead of relying on a single frame, it averages the distance over a 1-2 second rolling window. This filters out the AI's guessing noise, ensuring the app only registers an aspiration when it detects a true, sustained pull-back of the plunger.

---

## 5. Roboflow Model Training Settings
When generating a new dataset version and training the model, use these settings:

* **Preprocessing:** 
  * `Auto-Orient` (ON - fixes smartphone rotation metadata)
  * `Resize` (Stretch to 576x576 or 640x640)
* **Augmentation:** Not strictly necessary if the dataset contains a massive amount of real photos (e.g., 600+).
* **Training Architecture:** 
  * **RF-DETR (Preview):** Excellent accuracy.
  * **YOLOv11 (Fast):** Recommended alternative for extremely fast, real-time video streaming to prevent lag in the mobile app.
* **Weights:** Always select **Train from COCO Pretrained Weights**. This gives the AI a massive head start on understanding edges and shapes.
