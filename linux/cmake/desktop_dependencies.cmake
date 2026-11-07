# Android implementations of path_provider/shared_preferences bring in jni.
# DenucziTV does not use Java on Linux. Do not let a build host's optional JDK
# add libdartjni.so and a JVM runtime dependency to the desktop bundle.
set(CMAKE_DISABLE_FIND_PACKAGE_JNI TRUE)
# Also override JNI_FOUND from an earlier configure or an external cache entry.
set(JNI_FOUND FALSE)
