# Automatic Number Plate Recognition (ANPR)

A Flutter application for detecting vehicle license plates from camera or gallery images and extracting the plate number using on-device computer vision.

## Overview

This project combines a TensorFlow Lite object detection model with Google ML Kit text recognition. The application first identifies the license-plate region, crops the detected area, and then processes it with OCR to obtain readable plate text.

## Key Features

- Capture an image directly from the device camera
- Select an existing image from the gallery
- Detect license-plate regions using a TensorFlow Lite model
- Crop the detected plate area before OCR processing
- Extract plate text with Google ML Kit Text Recognition
- Run inference locally on the device
- Manage application state with BLoC and Provider

## Tech Stack

- Flutter and Dart
- TensorFlow Lite (`tflite_flutter`)
- Google ML Kit Text Recognition
- Camera and Image Picker
- Flutter BLoC
- Provider
- Image processing and cropping

## How It Works

```text
Camera or gallery image
        ↓
TensorFlow Lite plate detection
        ↓
Crop detected plate region
        ↓
Google ML Kit OCR
        ↓
Recognized license-plate text
```

## Project Structure

The project separates user interface, state handling, image processing, model inference, and OCR responsibilities so each part can be maintained independently.

## Getting Started

### Requirements

- Flutter SDK compatible with Dart `^3.10.3`
- Android Studio or Xcode
- A physical device or emulator with camera/gallery access

### Installation

```bash
git clone https://github.com/strhmdn14102004/Plat-License-Detector-Flutter.git
cd Plat-License-Detector-Flutter
flutter pub get
flutter run
```

The detection model is included at:

```text
assets/models/license_plate_detector_float16.tflite
```

## Permissions

Camera and photo-library permissions may be required depending on the target platform. Confirm the relevant Android manifest and iOS Info.plist entries before running the application.

## Development Notes

Detection and OCR accuracy can vary depending on lighting, image angle, motion blur, plate condition, and camera resolution. Future improvements may include confidence filtering, perspective correction, plate-format validation, and recognition history.

## Project Status

Portfolio and experimental computer-vision project. The application demonstrates an end-to-end on-device ANPR workflow in Flutter.

## Author

Developed by [Satria Ramadan](https://github.com/strhmdn14102004).