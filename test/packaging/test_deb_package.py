"""Integration checks for the real .deb; no root access or installation needed."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class DebianPackageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        package = os.environ.get("DENUCZITV_DEB")
        if package:
            cls.archive = Path(package).resolve()
        else:
            candidates = list((ROOT / "dist").glob("denuczitv_*.deb"))
            if len(candidates) != 1:
                raise RuntimeError("Build one package or set DENUCZITV_DEB to the archive to verify.")
            cls.archive = candidates[0]
        cls.temporary = tempfile.TemporaryDirectory(prefix="denuczitv-deb-test-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.extracted = Path(cls.temporary.name) / "extracted"
        cls.control = Path(cls.temporary.name) / "control"
        subprocess.run(["dpkg-deb", "--extract", cls.archive, cls.extracted], check=True)
        subprocess.run(["dpkg-deb", "--control", cls.archive, cls.control], check=True)

    def test_archive_ownership_and_permissions(self):
        with tempfile.TemporaryFile() as payload:
            subprocess.run(["dpkg-deb", "--fsys-tarfile", self.archive], stdout=payload, check=True)
            payload.seek(0)
            with tarfile.open(fileobj=payload) as archive:
                for member in archive:
                    self.assertEqual((member.uid, member.gid), (0, 0), member.name)
                    self.assertFalse(member.mode & 0o6022, member.name)
                    self.assertFalse(member.name.startswith("/"), member.name)
                    self.assertNotIn("..", Path(member.name).parts)

    def test_payload_checksums_and_third_party_licenses(self):
        for line in (self.control / "md5sums").read_text().splitlines():
            expected, name = line.split("  ", 1)
            payload = self.extracted / name
            actual = hashlib.md5(payload.read_bytes(), usedforsecurity=False).hexdigest()
            self.assertEqual(actual, expected, name)
        doc = self.extracted / "usr/share/doc/denuczitv"
        self.assertIn("MIT License", (doc / "copyright").read_text())
        self.assertTrue((doc / "third-party-notices.gz").is_file())

    def test_dependencies_include_playback_and_secure_storage(self):
        fields = (self.control / "control").read_text()
        self.assertIn("Package: denuczitv\n", fields)
        self.assertRegex(fields, r"Depends: .*\blibmpv\d+\b")
        self.assertIn("libsecret-1-0", fields)
        self.assertNotIn("libflutter", fields)

    def test_desktop_launcher_and_icons(self):
        launcher = self.extracted / "usr/bin/denuczitv"
        self.assertTrue(os.access(launcher, os.X_OK))
        self.assertIn('exec /usr/lib/denuczitv/denuczi_tv "$@"', launcher.read_text())
        desktops = list((self.extracted / "usr/share/applications").glob("*.desktop"))
        self.assertEqual(len(desktops), 1)
        subprocess.run(["desktop-file-validate", desktops[0]], check=True)
        icons = list((self.extracted / "usr/share/icons/hicolor").glob("*/apps/denuczitv.png"))
        self.assertEqual(len(icons), 9)

    def test_relocated_native_libraries(self):
        app = self.extracted / "usr/lib/denuczitv"
        for path in [app / "denuczi_tv", *sorted((app / "lib").glob("*.so*"))]:
            details = subprocess.check_output(["readelf", "--dynamic", path], text=True)
            for search in re.findall(r"\((?:RUNPATH|RPATH)\).*?\[(.*?)\]", details):
                self.assertIn(search, {"$ORIGIN", "$ORIGIN/lib"}, path.name)
            if "(NEEDED)" in details:
                linked = subprocess.check_output(["ldd", path], text=True)
                self.assertNotIn("not found", linked, path.name)
                self.assertNotIn(str(ROOT), linked, path.name)

    def test_original_bundle_is_unchanged(self):
        report = json.loads(self.archive.with_suffix(".build-info.json").read_text())
        target = {"amd64": "x64", "arm64": "arm64"}[report["architecture"]]
        bundle = ROOT / f"build/linux/{target}/release/bundle"
        for name, expected in report["bundle_elf_sha256"].items():
            with (bundle / name).open("rb") as stream:
                self.assertEqual(hashlib.file_digest(stream, "sha256").hexdigest(), expected, name)

    def test_rejects_stale_bundle_version(self):
        app = self.extracted / "usr/lib/denuczitv"
        with tempfile.TemporaryDirectory(prefix="denuczitv-stale-test-") as temporary:
            bundle = Path(temporary) / "bundle"
            shutil.copytree(app, bundle)
            metadata = bundle / "data/flutter_assets/version.json"
            metadata.write_text('{"version": "0.0.0", "build_number": "0"}')
            destination = Path(temporary) / "output"
            result = subprocess.run(
                ["python3", ROOT / "scripts/package_deb.py", "--bundle", bundle,
                 "--output-dir", destination], text=True, capture_output=True
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Rebuild before packaging", result.stderr)
            self.assertFalse(destination.exists())

    def test_rejects_missing_playback_plugin(self):
        app = self.extracted / "usr/lib/denuczitv"
        with tempfile.TemporaryDirectory(prefix="denuczitv-missing-library-test-") as temporary:
            bundle = Path(temporary) / "bundle"
            shutil.copytree(app, bundle)
            (bundle / "lib/libmedia_kit_video_plugin.so").unlink()
            destination = Path(temporary) / "output"
            result = subprocess.run(
                ["python3", ROOT / "scripts/package_deb.py", "--bundle", bundle,
                 "--output-dir", destination], text=True, capture_output=True
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Missing native dependencies", result.stderr)
            self.assertEqual(list(destination.glob("*.deb")), [])


if __name__ == "__main__":
    unittest.main()
