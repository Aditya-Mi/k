# Release builds are shrunk by R8. WorkManager's Room database is created by
# reflection (no-arg constructor), which R8 full mode strips: the app then
# crashes on start in androidx.startup.InitializationProvider.
-keep class * extends androidx.room.RoomDatabase { <init>(); }

# flutter_local_notifications stores scheduled reminders as JSON through Gson,
# which needs generic signatures kept.
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.** { *; }
