#!/usr/bin/env python3
"""Build a validated Debian binary package from an existing Flutter Linux bundle."""

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
PACKAGE = "denuczitv"
MAINTAINER = "Ignacio Sanguina <joseignaciosanguina@gmail.com>"
HOMEPAGE = "https://github.com/denuczi/DenucziTV"
ENV = {**os.environ, "LC_ALL": "C", "DPKG_COLORS": "never"}


def run(args, **kwargs):
    return subprocess.run(
        [str(arg) for arg in args], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ENV, **kwargs
    ).stdout.strip()


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write(path, text, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(mode)


def cmake_quote(value):
    separator = "="
    while f"]{separator}]" in str(value):
        separator += "="
    return f"[{separator}[{value}]{separator}]"


def dynamic(path):
    return run(["readelf", "--wide", "--dynamic", path])


def elf_files(directory):
    files = []
    for path in sorted(directory.rglob("*")):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as stream:
                if stream.read(4) == b"\x7fELF":
                    files.append(path)
    return files


def check_links(directory):
    for path in directory.rglob("*"):
        if path.is_symlink():
            if not path.resolve().is_relative_to(directory.resolve()) or not path.exists():
                raise ValueError(f"Broken or external bundle symlink: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, help="Flutter release bundle directory")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist")
    parser.add_argument("--revision", default="1", help="Debian packaging revision (default: 1)")
    args = parser.parse_args()
    required = ["dpkg", "dpkg-deb", "dpkg-shlibdeps", "dpkg-architecture", "readelf",
                "ldd", "cmake", "desktop-file-validate"]
    missing = [tool for tool in required if shutil.which(tool) is None]
    if missing:
        raise ValueError("Missing packaging tools: " + ", ".join(missing)
                         + ". Install dpkg-dev binutils cmake desktop-file-utils.")
    if not re.fullmatch(r"[1-9][0-9]*", args.revision):
        raise ValueError("The Debian revision must be a positive integer.")

    arch = run(["dpkg-architecture", "-qDEB_HOST_ARCH"])
    targets = {"amd64": ("x64", "Advanced Micro Devices X86-64"),
               "arm64": ("arm64", "AArch64")}
    if arch not in targets:
        raise ValueError(f"Unsupported architecture: {arch}. Supported: amd64, arm64.")
    target, machine = targets[arch]
    bundle = (args.bundle or ROOT / f"build/linux/{target}/release/bundle").resolve()
    required_files = ["denuczi_tv", "lib/libapp.so", "lib/libflutter_linux_gtk.so",
                      "data/icudtl.dat", "data/flutter_assets/version.json",
                      "data/flutter_assets/NOTICES.Z"]
    for name in required_files:
        if not (bundle / name).is_file():
            raise ValueError(f"Incomplete release bundle: missing {name}. "
                             "Run flutter build linux --release first.")
    if not os.access(bundle / "denuczi_tv", os.X_OK):
        raise ValueError("The bundle executable is not executable.")
    check_links(bundle)
    source_elfs = elf_files(bundle)
    for path in source_elfs:
        header = run(["readelf", "--file-header", path])
        if not re.search(r"Machine:\s*" + re.escape(machine) + r"\s*$", header, re.M):
            raise ValueError(f"ELF architecture does not match {arch}: {path.name}")

    match = re.search(r"^version:\s*([^\s#]+)", (ROOT / "pubspec.yaml").read_text(), re.M)
    if not match:
        raise ValueError("pubspec.yaml has no version.")
    flutter_version = match.group(1).strip("\"'")
    version, _, build_number = flutter_version.partition("+")
    built = json.loads((bundle / "data/flutter_assets/version.json").read_text())
    if built.get("version") != version or str(built.get("build_number", "")) != build_number:
        raise ValueError("The bundle version differs from pubspec.yaml. Rebuild before packaging.")
    # Debian sorts prereleases before their final version; retain Flutter build metadata.
    deb_version = flutter_version.replace("-", "~", 1) + "-" + args.revision
    run(["dpkg", "--validate-version", deb_version])
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch is None:
        try:
            epoch = run(["git", "-C", ROOT, "log", "-1", "--format=%ct"])
        except subprocess.CalledProcessError:
            epoch = str(int((bundle / "denuczi_tv").stat().st_mtime))
    if not epoch.isdecimal():
        raise ValueError("SOURCE_DATE_EPOCH must be a non-negative integer.")
    ENV["SOURCE_DATE_EPOCH"] = epoch
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    name = f"{PACKAGE}_{deb_version}_{arch}"
    original_hashes = {str(p.relative_to(bundle)): sha256(p) for p in source_elfs}

    # Work on a private copy: never patch the user's original release bundle.
    with tempfile.TemporaryDirectory(prefix="denuczitv-deb-") as temporary:
        work = Path(temporary)
        stage = work / "debian" / PACKAGE
        control = stage / "DEBIAN"
        control.mkdir(parents=True)
        app = stage / "usr/lib" / PACKAGE
        shutil.copytree(bundle, app, symlinks=True)
        binaries = elf_files(app)
        for path in binaries:
            old = re.findall(r"\((?:RUNPATH|RPATH)\).*?\[(.*?)\]", dynamic(path))
            desired = "$ORIGIN/lib" if path == app / "denuczi_tv" else "$ORIGIN"
            if old and old != [desired]:
                if len(old) != 1:
                    raise ValueError(f"Multiple runtime search paths in {path.name}.")
                script = work / "rpath.cmake"
                script.write_text(
                    f"file(RPATH_CHANGE FILE {cmake_quote(path)} "
                    f"OLD_RPATH {cmake_quote(old[0])} NEW_RPATH {cmake_quote(desired)})\n"
                )
                run(["cmake", "-P", script])
            paths = re.findall(r"\((?:RUNPATH|RPATH)\).*?\[(.*?)\]", dynamic(path))
            if any(entry not in {"$ORIGIN", "$ORIGIN/lib"} for entry in paths):
                raise ValueError(f"Non-relocatable runtime search path in {path.name}.")
            resolved = run(["ldd", path]) if "(NEEDED)" in dynamic(path) else ""
            if "not found" in resolved:
                raise ValueError(f"Missing native dependencies for {path.name}:\n{resolved}")
            # Loading must work with the staged libraries, not the source workspace.
            if str(ROOT) in resolved or str(bundle) in resolved:
                raise ValueError(f"A staged binary still loads libraries from the source tree: {path.name}")

        write(stage / "usr/bin/denuczitv",
              '#!/bin/sh\nexec /usr/lib/denuczitv/denuczi_tv "$@"\n', 0o755)
        application_id = re.search(
            r'set\(APPLICATION_ID\s+"([A-Za-z0-9_.-]+)"\)',
            (ROOT / "linux/CMakeLists.txt").read_text()
        )
        if not application_id:
            raise ValueError("Cannot determine the GTK application ID.")
        desktop = stage / f"usr/share/applications/{application_id.group(1)}.desktop"
        write(desktop, "[Desktop Entry]\nType=Application\nName=DenucziTV\n"
              "Comment=Play media from your IPTV provider\nExec=denuczitv\n"
              "TryExec=denuczitv\nIcon=denuczitv\nTerminal=false\n"
              "Categories=AudioVideo;Video;Player;\n"
              f"StartupWMClass={application_id.group(1)}\n")
        run(["desktop-file-validate", desktop])
        for size in [16, 24, 32, 48, 64, 128, 256, 512, 1024]:
            icon = ROOT / f"assets/branding/icon_{size}.png"
            if not icon.is_file():
                raise ValueError(f"Missing branding icon: {icon.name}")
            dest = stage / f"usr/share/icons/hicolor/{size}x{size}/apps/denuczitv.png"
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(icon, dest)

        doc = stage / "usr/share/doc" / PACKAGE
        write(doc / "copyright", (ROOT / "LICENSE").read_text()
              + "\nThird-party notices: see third-party-notices.gz and the bundled NOTICES.Z.\n")
        write(doc / "README.Debian", "DenucziTV\n\n"
              "Launch with denuczitv or the desktop application menu.\n"
              "Credentials require an active desktop Secret Service, such as GNOME Keyring\n"
              "or a configured KWallet Secret Service implementation.\n"
              "No channels, playlists, or subscriptions are included.\n"
              "This package targets the native libraries of the distribution used to build it.\n")
        notices = gzip.decompress((app / "data/flutter_assets/NOTICES.Z").read_bytes())
        (doc / "third-party-notices.gz").write_bytes(gzip.compress(notices, mtime=0))

        # Real symbols/shlibs data supplies package names and minimum ABI versions.
        # Do not use --ignore-missing-info: unresolved public libraries must fail.
        write(work / "debian/control", f"Source: {PACKAGE}\nSection: video\n"
              f"Priority: optional\nMaintainer: {MAINTAINER}\n\n"
              f"Package: {PACKAGE}\nArchitecture: any\n"
              "Description: Desktop IPTV player\n")
        deps_process = subprocess.run(
            ["dpkg-shlibdeps", "-O", f"-l{app / 'lib'}",
             *[f"-e{path}" for path in binaries]], cwd=work, env=ENV,
            check=True, text=True, capture_output=True
        )
        dep_lines = [line for line in deps_process.stdout.splitlines()
                     if line.startswith("shlibs:Depends=")]
        if len(dep_lines) != 1:
            raise ValueError("dpkg-shlibdeps did not produce exactly one dependency list.")
        depends = dep_lines[0].partition("=")[2]
        if not re.search(r"\blibmpv\d+\b", depends):
            raise ValueError("The dependency scan did not detect libmpv; review the playback bundle.")
        size = sum(p.lstat().st_size for p in stage.rglob("*") if p.is_file())
        write(control / "control", f"Package: {PACKAGE}\nVersion: {deb_version}\n"
              f"Section: video\nPriority: optional\nArchitecture: {arch}\n"
              f"Maintainer: {MAINTAINER}\nInstalled-Size: {(size + 1023) // 1024}\n"
              f"Depends: {depends}\nRecommends: gnome-keyring | kwallet6 | kwalletmanager\n"
              f"Homepage: {HOMEPAGE}\nDescription: Desktop IPTV player for user-provided services\n"
              " Flutter desktop application with live TV, movies, series, downloads,\n"
              " and a local personal library. No media or subscriptions are included.\n")
        # Normalize permissions and timestamps; ownership is set by dpkg-deb.
        for path in [stage, *sorted(stage.rglob("*"))]:
            if not path.is_symlink():
                path.chmod(0o755 if path.is_dir() or path == app / "denuczi_tv"
                           or path == stage / "usr/bin/denuczitv" else 0o644)
        checksums = []
        for path in sorted((stage / "usr").rglob("*")):
            if path.is_file() and not path.is_symlink():
                checksums.append(f"{hashlib.md5(path.read_bytes(), usedforsecurity=False).hexdigest()}"
                                 f"  {path.relative_to(stage)}\n")
        write(control / "md5sums", "".join(checksums))
        for path in [*stage.rglob("*"), stage]:
            os.utime(path, (int(epoch), int(epoch)), follow_symlinks=False)

        archive = work / f"{name}.deb"
        print(f"Packaging {deb_version} ({arch})\nDepends: {depends}", flush=True)
        run(["dpkg-deb", "--root-owner-group", "--threads-max=1", "-Zxz", "-z6",
             "--build", stage, archive])
        run(["dpkg-deb", "--info", archive])
        if shutil.which("lintian"):
            result = subprocess.run(["lintian", "--fail-on", "error", str(archive)], env=ENV)
            if result.returncode:
                raise ValueError("Lintian rejected the package; review its output.")

        # Publish only after all mandatory checks pass. Temporary files stay on the
        # destination filesystem so the final replacement is atomic.
        dest = output / archive.name
        with tempfile.NamedTemporaryFile(dir=output, prefix=".denuczitv-", delete=False) as stream:
            pending = Path(stream.name)
        try:
            shutil.copyfile(archive, pending)
            pending.chmod(0o644)
            pending.replace(dest)
        finally:
            pending.unlink(missing_ok=True)
        write(output / f"{name}.deb.sha256", f"{sha256(dest)}  {dest.name}\n")
        write(output / f"{name}.dependencies.log", deps_process.stderr)
        report = {
            "package": PACKAGE, "version": deb_version, "architecture": arch,
            "flutter_version": flutter_version, "source_date_epoch": int(epoch),
            "depends": depends, "sha256": sha256(dest),
            "bundle_elf_sha256": original_hashes,
            "lintian_ran": shutil.which("lintian") is not None,
            "build_distribution": platform.freedesktop_os_release(),
        }
        try:
            report["source_commit"] = run(["git", "-C", ROOT, "rev-parse", "HEAD"])
            report["source_dirty"] = bool(run(["git", "-C", ROOT, "status", "--porcelain"]))
        except subprocess.CalledProcessError:
            report["source_commit"] = None
        write(output / f"{name}.build-info.json", json.dumps(report, indent=2) + "\n")
        print(f"Created: {dest}\nSHA256: {report['sha256']}")
        if not report["lintian_ran"]:
            print("Lintian is not installed; archive, dependency, ELF, and desktop checks passed.")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(f"Error: command failed: {' '.join(map(str, error.cmd))}\n"
              f"{error.stderr or ''}", file=sys.stderr)
        sys.exit(1)
    except (ValueError, OSError, json.JSONDecodeError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
