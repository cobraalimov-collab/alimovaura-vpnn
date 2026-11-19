# R8 / ProGuard rules for release builds (isMinifyEnabled = true).

# WireGuard tunnel library (JNI + reflection) must not be stripped or renamed.
-keep class com.wireguard.** { *; }
-dontwarn com.wireguard.**

# Flutter plugin glue for the VPN engine.
-keep class com.billion.** { *; }
-dontwarn com.billion.**

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }
