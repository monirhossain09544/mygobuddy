# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# Keep all Stripe classes
-keep class com.stripe.** { *; }
-keepclassmembers class com.stripe.** { *; }

# Keep Stripe Push Provisioning classes specifically
-keep class com.stripe.android.pushProvisioning.** { *; }
-keepclassmembers class com.stripe.android.pushProvisioning.** { *; }

# Keep specific missing classes mentioned in the build error
-keep class com.stripe.android.pushProvisioning.EphemeralKeyUpdateListener { *; }
-keep class com.stripe.android.pushProvisioning.PushProvisioningActivity$* { *; }
-keep class com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$* { *; }
-keep class com.stripe.android.pushProvisioning.PushProvisioningActivityStarter { *; }
-keep class com.stripe.android.pushProvisioning.PushProvisioningEphemeralKeyProvider { *; }

# Keep all Stripe Android SDK classes and inner classes
-keep class com.stripe.android.** { *; }
-keepclassmembers class com.stripe.android.** { *; }

# Keep React Native Stripe SDK classes
-keep class com.reactnativestripesdk.** { *; }
-keepclassmembers class com.reactnativestripesdk.** { *; }

# Keep all React Native Stripe SDK push provisioning classes
-keep class com.reactnativestripesdk.pushprovisioning.** { *; }
-keepclassmembers class com.reactnativestripesdk.pushprovisioning.** { *; }

# Keep classes that use reflection
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Prevent R8 from removing classes that are referenced via reflection or JNI
-keepclassmembers class * {
    @com.stripe.android.** *;
}

# Keep classes with @Keep annotation
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# Keep Google Play Core classes for dynamic feature delivery
-keep class com.google.android.play.core.** { *; }
-keepclassmembers class com.google.android.play.core.** { *; }

# Keep specific Google Play Core classes mentioned in build error
-keep class com.google.android.play.core.splitcompat.SplitCompatApplication { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# Keep Google Crypto Tink classes for cryptographic operations
-keep class com.google.crypto.tink.** { *; }
-keepclassmembers class com.google.crypto.tink.** { *; }

# Keep specific Tink crypto classes mentioned in build error
-keep class com.google.crypto.tink.subtle.Ed25519Sign { *; }
-keep class com.google.crypto.tink.subtle.Ed25519Sign$KeyPair { *; }
-keep class com.google.crypto.tink.subtle.Ed25519Verify { *; }
-keep class com.google.crypto.tink.subtle.X25519 { *; }

# Keep Flutter embedding classes that reference Play Core
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-keep class io.flutter.embedding.android.FlutterPlayStoreSplitApplication { *; }

# Prevent warnings for missing Google Play Core classes
-dontwarn com.google.android.play.core.**
-dontwarn com.google.crypto.tink.**

# Prevent warnings for missing Stripe classes
-dontwarn com.stripe.**
-dontshrink
-dontoptimize

# Keep all classes in Stripe packages with all their members
-keep class com.stripe.** { *; }
-keep interface com.stripe.** { *; }
-keep enum com.stripe.** { *; }

# Keep all React Native Stripe SDK classes with all their members
-keep class com.reactnativestripesdk.** { *; }
-keep interface com.reactnativestripesdk.** { *; }
-keep enum com.reactnativestripesdk.** { *; }

# Keep classes with Stripe or stripe in their names
-keep class **.*Stripe*.** { *; }
-keep class **.*stripe*.** { *; }

# Keep class members annotated with Stripe or React Native Stripe SDK annotations
-keepclassmembers class ** {
    @com.stripe.** *;
    @com.reactnativestripesdk.** *;
}

# Keep class names of Stripe and React Native Stripe SDK
-keepnames class com.stripe.**
-keepnames class com.reactnativestripesdk.**

# Keep public, private, and protected members of Stripe and React Native Stripe SDK classes
-keepclassmembers class com.stripe.** {
    public *;
    private *;
    protected *;
}

-keepclassmembers class com.reactnativestripesdk.** {
    public *;
    private *;
    protected *;
}
