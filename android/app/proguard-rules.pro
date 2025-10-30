# TensorFlow Lite GPU Delegate
-keep class org.tensorflow.** { *; }
-dontwarn org.tensorflow.**

# CameraX
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# Flutter Plugins
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Prevent removing annotations (for ML Kit)
-keepattributes *Annotation*
