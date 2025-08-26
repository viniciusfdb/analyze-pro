# Mantém as anotações para evitar remoção pelo R8
-keep class javax.annotation.* { *; }
-keep class javax.annotation.concurrent.* { *; }
-keep class com.google.crypto.tink.** { *; }
-keep class androidx.annotation.* { *; }

# Mantém anotações usadas pelo Tink
-keepattributes *Annotation*

# Impede que algumas classes sejam minificadas
-dontwarn javax.annotation.**
-dontwarn com.google.crypto.tink.**
