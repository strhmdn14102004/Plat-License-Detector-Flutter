####################################
# ML KIT
####################################
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.**

####################################
# TFLITE
####################################
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
-dontwarn org.tensorflow.lite.**

####################################
# CAMERA (CameraX)
####################################
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

####################################
# IMAGE PICKER
####################################
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**
