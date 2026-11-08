# DenucziTV does not use the optional desktop JNI bridge. Hosted Windows
# runners include Java; finding it would introduce an unused JVM dependency.
# Load this policy through CMAKE_TOOLCHAIN_FILE on a fresh build tree.
set(CMAKE_DISABLE_FIND_PACKAGE_JNI TRUE CACHE BOOL
    "Disable the unused desktop JNI runtime for DenucziTV" FORCE)
