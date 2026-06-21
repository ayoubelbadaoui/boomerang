# FFmpegKit: native libraries register their methods via JNI_OnLoad against
# these exact class/method names. R8 must not rename or strip them, otherwise
# RegisterNatives fails at startup with "Bad JNI version returned from
# JNI_OnLoad: 0" and the whole plugin registration (incl. Firebase) aborts.
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-keep class com.arthenica.** { *; }

# Flutter embedding / plugin registrant (defensive; Flutter ships most of these).
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep native method names everywhere (JNI).
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter references Google Play Core (deferred components / split install)
# classes that aren't bundled because this app doesn't use dynamic feature
# modules. Tell R8 to ignore the missing references.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
