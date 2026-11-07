"""Exercise the real JNI plugin CMake configuration with simulated JDK discovery."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
JNI_PLUGIN = ROOT / "linux/flutter/ephemeral/.plugin_symlinks/jni/linux"


class LinuxJniPolicyTest(unittest.TestCase):
    def configure(self, policy, cached_found=False):
        self.assertTrue(JNI_PLUGIN.is_dir(), "Run flutter pub get to prepare the JNI plugin.")
        with tempfile.TemporaryDirectory(prefix="denuczitv-jni-policy-") as temporary:
            source = Path(temporary)
            # A real JDK is unnecessary: this module simulates successful discovery
            # for the upstream plugin, which otherwise skips its native library.
            (source / "FindJNI.cmake").write_text("set(JNI_FOUND TRUE)\n")
            (source / "CMakeLists.txt").write_text(
                'cmake_minimum_required(VERSION 3.10)\n'
                'project(jni_policy_test LANGUAGES C CXX)\n'
                'list(PREPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}")\n'
                'if(DESKTOP_POLICY)\n'
                f'  include("{ROOT / "linux/cmake/desktop_dependencies.cmake"}")\n'
                'endif()\n'
                f'add_subdirectory("{JNI_PLUGIN}" jni-plugin)\n'
                'if(TARGET jni)\n'
                '  file(WRITE "${CMAKE_BINARY_DIR}/jni-target.txt" "present")\n'
                'else()\n'
                '  file(WRITE "${CMAKE_BINARY_DIR}/jni-target.txt" "absent")\n'
                'endif()\n'
            )
            command = ["cmake", "-S", str(source), "-B", str(source / "build"),
                       f"-DDESKTOP_POLICY={'ON' if policy else 'OFF'}"]
            if cached_found:
                command.append("-DJNI_FOUND:BOOL=TRUE")
            result = subprocess.run(command, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return (source / "build/jni-target.txt").read_text()

    def test_upstream_plugin_builds_jni_when_a_jdk_is_discovered(self):
        self.assertEqual(self.configure(policy=False), "present")

    def test_linux_policy_prevents_optional_jni_build(self):
        self.assertEqual(self.configure(policy=True), "absent")

    def test_linux_policy_overrides_stale_jni_cache(self):
        self.assertEqual(self.configure(policy=True, cached_found=True), "absent")


if __name__ == "__main__":
    unittest.main()
