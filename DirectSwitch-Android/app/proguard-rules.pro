# Regole ProGuard DirectSwitch
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keep class com.directswitch.android.protocol.** { *; }

# kotlinx.serialization: modelli @Serializable (anche fuori da .protocol, es. SmsTransferRecord)
-keepattributes RuntimeVisibleAnnotations,AnnotationDefault
-keep,includedescriptorclasses class com.directswitch.android.**$$serializer { *; }
-keepclassmembers @kotlinx.serialization.Serializable class com.directswitch.android.** {
    *** Companion;
    *** INSTANCE;
    kotlinx.serialization.KSerializer serializer(...);
}
-keepclasseswithmembers class com.directswitch.android.** {
    kotlinx.serialization.KSerializer serializer(...);
}
# OkHttp / Okio
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
# Play Billing
-keep class com.android.vending.billing.** { *; }
