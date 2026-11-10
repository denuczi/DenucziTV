"""Static checks for the Microsoft Store MSIX channel.

These tests do not build, sign, install, or run Windows packages. They protect
the reviewed configuration, artifact separation, workflow permissions, and
private-key handling so a Windows runner can perform the native checks later.
"""

from pathlib import Path
import re
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
PUBSPEC = ROOT / "pubspec.yaml"
LOCKFILE = ROOT / "pubspec.lock"
SCRIPT = ROOT / "scripts/package-msix.ps1"
WORKFLOW = ROOT / ".github/workflows/microsoft-store.yml"
STORE_DOC = ROOT / "docs/MICROSOFT_STORE.md"
PRIVACY = ROOT / "docs/privacy.html"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def load_yaml(path: Path):
    return yaml.safe_load(read(path))


class MsixConfigurationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pubspec = load_yaml(PUBSPEC)
        cls.lock = load_yaml(LOCKFILE)
        cls.config = cls.pubspec["msix_config"]

    def test_public_version_is_unchanged(self):
        self.assertEqual(self.pubspec["version"], "0.6.3+1")

    def test_msix_is_a_development_dependency_only(self):
        self.assertIn("msix", self.pubspec["dev_dependencies"])
        self.assertEqual(self.pubspec["dev_dependencies"]["msix"], "^3.18.0")
        self.assertNotIn("msix", self.pubspec["dependencies"])
        package = self.lock["packages"]["msix"]
        self.assertEqual(package["version"], "3.18.0")
        self.assertEqual(package["dependency"], "direct dev")

    def test_partner_center_identity_and_package_metadata(self):
        expected = {
            "identity_name": "IgnacioSanguina.DenucziTV",
            "publisher": "CN=055E0D46-1999-438C-9CDB-4069928369ED",
            "publisher_display_name": "Ignacio Sanguina",
            "display_name": "DenucziTV",
            "msix_version": "1.6.3.0",
            "architecture": "x64",
            "build_windows": False,
            "languages": "en-US,es-ES",
            "capabilities": "runFullTrust",
            "output_path": "build/store_msix",
            "output_name": "DenucziTV-0.6.3-x64",
        }
        for key, value in expected.items():
            self.assertEqual(self.config.get(key), value, key)
        self.assertNotIn("store", self.config)
        self.assertNotIn("certificate_path", self.config)
        self.assertNotIn("certificate_password", self.config)
        self.assertTrue((ROOT / self.config["logo_path"]).is_file())

    def test_package_version_is_valid_for_the_store(self):
        version = self.config["msix_version"]
        self.assertRegex(version, r"^\d+\.\d+\.\d+\.\d+$")
        parts = [int(part) for part in version.split(".")]
        self.assertNotEqual(parts[0], 0)
        self.assertEqual(parts[3], 0)
        for part in parts:
            self.assertGreaterEqual(part, 0)
            self.assertLessEqual(part, 65535)
        self.assertEqual(version, "1.6.3.0")
        self.assertEqual(version.split(".")[1:3], ["6", "3"])


class MsixWorkflowTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = read(WORKFLOW)
        cls.document = load_yaml(WORKFLOW)
        cls.triggers = cls.document.get("on", cls.document.get(True))
        cls.script = read(SCRIPT)
        cls.jobs = cls.document["jobs"]
        cls.job = cls.jobs["package"]
        cls.steps = cls.job["steps"]

    def test_workflow_is_manual_and_does_not_publish_releases(self):
        self.assertEqual(self.document["name"], "Microsoft Store MSIX")
        self.assertEqual(set(self.triggers), {"workflow_dispatch"})
        self.assertEqual(self.document["permissions"], {"contents": "read"})
        self.assertNotIn("contents: write", self.text)
        for forbidden in (
            "gh release",
            "softprops/action-gh-release",
            "actions/create-release",
            "pypi",
            "secrets.",
        ):
            self.assertNotIn(forbidden, self.text.lower())
        self.assertNotIn("release_tag", self.text)
        self.assertNotIn("refs/tags/", self.text)

    def test_workflow_uses_a_windows_runner_and_pinned_flutter(self):
        self.assertEqual(self.job["runs-on"], "windows-2022")
        self.assertEqual(self.job["defaults"]["run"]["shell"], "pwsh")
        setup = next(step for step in self.steps if step.get("name") == "Set up Flutter")
        self.assertEqual(setup["with"]["flutter-version"], "3.47.9")
        self.assertEqual(setup["with"]["channel"], "stable")
        self.assertEqual(setup["with"]["architecture"], "x64")

    def test_workflow_uses_one_revision_for_tools_code_and_tests(self):
        inputs = self.triggers["workflow_dispatch"]["inputs"]
        self.assertIn("source_ref", inputs)
        self.assertEqual(inputs["source_ref"]["default"], "main")
        self.assertIn("confirm_public_version", inputs)

        checkouts = [
            step for step in self.steps if step.get("uses") == "actions/checkout@v5"
        ]
        self.assertEqual(len(checkouts), 1)
        self.assertNotIn('actions/checkout@v4', self.text)
        source = checkouts[0]
        self.assertEqual(source["with"]["ref"], "${{ inputs.source_ref }}")
        self.assertEqual(source["with"]["path"], "source")
        self.assertFalse(source["with"]["persist-credentials"])

        names = [step.get("name", "") for step in self.steps]
        self.assertNotIn("Check out packaging tools", names)
        self.assertIn("Validate packaging tooling from the same revision", names)

        for step_name in (
            "Run Flutter tests",
            "Run MSIX packaging tests",
            "Run MSIX packager behavior tests",
        ):
            step = next(step for step in self.steps if step.get("name") == step_name)
            self.assertEqual(step["working-directory"], "source")

        build = next(
            step for step in self.steps if step.get("name") == "Build and package MSIX from the same revision"
        )["run"]
        self.assertIn(".\\source\\scripts\\package-msix.ps1", build)
        self.assertIn("-ProjectRoot .\\source", build)
        self.assertIn("-ExpectedSourceCommit $env:SOURCE_SHA", build)

    def test_workflow_validates_the_tooling_revision(self):
        verify = next(
            step
            for step in self.steps
            if step.get("name") == "Validate packaging tooling from the same revision"
        )
        self.assertEqual(verify["working-directory"], "source")
        for path in (
            "scripts/package-msix.ps1",
            "packaging/windows/flutter-toolchain.cmake",
            "test/packaging/test_msix_package.py",
            "pubspec.yaml",
            "pubspec.lock",
        ):
            self.assertIn(path, verify["run"])
        self.assertIn("$sha.Trim() -cne $env:SOURCE_SHA", verify["run"])
        self.assertIn("Parser]::ParseFile", verify["run"])

    def test_workflow_records_the_exact_commit(self):
        record = next(step for step in self.steps if step.get("name") == "Resolve and record the exact source revision")
        self.assertIn("git -C source rev-parse HEAD", record["run"])
        self.assertIn("SOURCE_SHA", record["run"])
        self.assertIn("^[0-9a-f]{40}$", record["run"])
        self.assertIn("git -C source status --porcelain", record["run"])
        self.assertIn("The source checkout is not clean", record["run"])
        self.assertIn("describe --always --tags --dirty", record["run"])

    def test_native_revision_commands_run_to_completion(self):
        # Select-Object -First can terminate native executables prematurely,
        # leaving LASTEXITCODE at -1 even when stdout contained a valid SHA.
        for step_name in (
            "Resolve and record the exact source revision",
            "Validate packaging tooling from the same revision",
        ):
            step = next(step for step in self.steps if step.get("name") == step_name)
            self.assertNotRegex(
                step["run"],
                r"git\b[^\n]*\|\s*Select-Object\s+-First",
            )
            self.assertIn("$gitExitCode = $LASTEXITCODE", step["run"])
        self.assertNotRegex(
            self.script,
            r"(?:git\b|\$vswhere\b)[^\n]*\|\s*Select-Object\s+-First",
        )
        self.assertIn("$sourceCommit = & git -C $root rev-parse HEAD", self.script)
        self.assertIn("$sourceDescribe = & git -C $root describe --always --tags --dirty", self.script)

    def test_workflow_runs_quality_gates_and_the_packager(self):
        names = [step.get("name", "") for step in self.steps]
        for expected in (
            "Generate localization",
            "Check formatting",
            "Analyze application",
            "Run Flutter tests",
            "Run MSIX packaging tests",
            "Run MSIX packager behavior tests",
            "Verify the source is still clean before packaging",
            "Build and package MSIX from the same revision",
            "Reject private key artifacts",
        ):
            self.assertIn(expected, names)
        lock = next(
            step for step in self.steps if step.get("name") == "Verify the dependency lockfile is unchanged"
        )
        self.assertIn("git status --porcelain -- pubspec.yaml pubspec.lock", lock["run"])
        clean = next(
            step for step in self.steps if step.get("name") == "Verify the source is still clean before packaging"
        )
        self.assertEqual(clean["working-directory"], "source")
        self.assertIn("git status --porcelain", clean["run"])
        self.assertIn("modified tracked source files", clean["run"])

    def test_artifacts_are_separate_and_never_include_private_keys(self):
        uploads = [step for step in self.steps if step.get("uses") == "actions/upload-artifact@v4"]
        self.assertEqual(len(uploads), 2)
        paths = "\n".join(step["with"]["path"] for step in uploads)
        self.assertIn("DenucziTV-0.6.3-x64-store.msix", paths)
        self.assertIn("DenucziTV-0.6.3-x64-qa.msix", paths)
        self.assertIn("DenucziTV-0.6.3-x64-qa.cer", paths)
        self.assertNotIn(".pfx", paths)
        self.assertNotIn(".p12", paths)
        self.assertNotIn(".pem", paths)
        self.assertNotIn(".key", paths)
        for upload in uploads:
            self.assertEqual(upload["with"]["if-no-files-found"], "error")
            self.assertEqual(upload["with"]["retention-days"], 14)

    def test_packaging_script_builds_once_and_reuses_the_bundle(self):
        self.assertIn(
            'flutter build windows --release "--dart-define=$storeBuildDefine"',
            self.script,
        )
        self.assertIn("$storeBuildDefine = 'DENUCZI_STORE_BUILD=true'", self.script)
        self.assertEqual(self.script.count("Invoke-MsixCreate -Root"), 1)
        self.assertRegex(self.script, r"'--build-windows',\s*'false'")
        self.assertRegex(self.script, r"'--install-certificate',\s*'false'")
        self.assertRegex(self.script, r"'--sign-msix',\s*'false'")
        self.assertIn("'--store'", self.script)
        self.assertIn(
            "Invoke-MsixCreate -Root $root -OutputPath $outputRoot -OutputName $storeName -Store",
            self.script,
        )
        self.assertIn(
            'Copy-Item -LiteralPath $storeMsix -Destination $qaMsix -ErrorAction Stop',
            self.script,
        )
        self.assertIn('The unsigned QA copy differs from the Store package.', self.script)
        self.assertIn('Signing the QA copy modified the unsigned Store package.', self.script)
        self.assertNotIn('Invoke-MsixCreate -Root $root -OutputPath $qaDirectory', self.script)
        self.assertNotIn("--certificate-password", self.script)
        self.assertNotIn("--certificate-path", self.script)

    def test_script_binds_the_packager_to_the_expected_revision(self):
        self.assertIn("[string]$ExpectedSourceCommit = ''", self.script)
        self.assertIn("$expectedCommit = $ExpectedSourceCommit.Trim()", self.script)
        self.assertIn("$sourceCommit -cne $expectedCommit", self.script)
        self.assertIn(
            "The packaging script must belong to the same source revision as ProjectRoot",
            self.script,
        )
        self.assertIn("$scriptRoot.StartsWith", self.script)
        self.assertIn(
            "Join-Path $root 'packaging\\windows\\flutter-toolchain.cmake'",
            self.script,
        )
        self.assertIn("sourceDescribe = $sourceDescribe", self.script)
        self.assertIn("sourceCommitVerified = $true", self.script)

    def test_script_creates_store_and_qa_packages_with_separate_names(self):
        self.assertIn("$storeName = \"$expectedOutputName-store\"", self.script)
        self.assertIn("$qaName = \"$expectedOutputName-qa\"", self.script)
        self.assertIn("$qaDirectory = Join-Path $outputRoot 'qa'", self.script)
        self.assertNotIn("$storeDirectory", self.script)
        self.assertIn("Get-FileHash -LiteralPath $Path -Algorithm SHA256", self.script)
        self.assertIn("$storeHash = Write-Sha256Sidecar -Path $storeMsix", self.script)
        self.assertIn("$qaHash = Write-Sha256Sidecar -Path $qaMsix", self.script)

    def test_script_uses_and_cleans_an_ephemeral_qa_certificate(self):
        self.assertIn("CN=055E0D46-1999-438C-9CDB-4069928369ED", self.script)
        self.assertIn("New-SelfSignedCertificate", self.script)
        self.assertIn("-Subject $Subject", self.script)
        self.assertIn("-KeyExportPolicy NonExportable", self.script)
        self.assertNotIn("-KeyExportPolicy Exportable", self.script)
        self.assertIn("-KeySpec Signature", self.script)
        self.assertIn("-KeyUsage DigitalSignature", self.script)
        self.assertIn("-TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3')", self.script)
        self.assertIn("Assert-QaCertificatePurposes -Certificate $certificate", self.script)
        self.assertIn("[Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]", self.script)
        self.assertIn("[Security.Cryptography.X509Certificates.X509KeyUsageExtension]", self.script)
        self.assertIn("$oid.Value -ceq $codeSigningOid", self.script)
        self.assertNotIn("$certificate.EnhancedKeyUsageList", self.script)
        self.assertIn("X509KeyUsageFlags]::DigitalSignature", self.script)
        self.assertIn("HasPrivateKey", self.script)
        self.assertIn("Export-Certificate", self.script)
        self.assertIn("$qaInfo['certificateStore'] = 'CurrentUser\\My'", self.script)
        self.assertIn("sign /fd SHA256 /s My /sha1 $qaCertificate.Thumbprint $qaMsix", self.script)
        self.assertIn("verify /pa /v", self.script)
        self.assertIn("Remove-TrustedPeopleCertificate", self.script)
        self.assertIn("Assert-QaTrustStoreWritable", self.script)
        self.assertIn("-DeleteKey", self.script)
        self.assertIn("Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force", self.script)

    def test_qa_trust_is_machine_scoped_and_never_a_root_authority(self):
        # MSIX App Installer uses LocalMachine/TrustedPeople for self-signed
        # packages. CurrentUser/TrustedPeople did not establish trust in CI.
        self.assertIn('function New-QaTrustStore {', self.script)
        self.assertIn('StoreName]::TrustedPeople', self.script)
        self.assertIn('StoreLocation]::LocalMachine', self.script)
        self.assertNotIn('StoreLocation]::CurrentUser', self.script)
        self.assertNotIn('StoreName]::Root', self.script)
        self.assertIn('Assert-QaTrustStoreWritable', self.script)
        self.assertLess(
            self.script.index('Assert-QaTrustStoreWritable\n'),
            self.script.index('& flutter build windows --release'),
        )
        self.assertIn('The QA certificate is already in LocalMachine', self.script)
        self.assertIn('FindByThumbprint', self.script)
        self.assertIn('QA certificate temporarily trusted in LocalMachine', self.script)
        self.assertIn('verify /pa /v $qaMsix', self.script)
        self.assertIn('VerifiedWithTemporaryMachineTrust', self.script)
        self.assertIn("$qaInfo['verificationTrustStore'] = 'LocalMachine\\TrustedPeople'", self.script)
        self.assertIn("$qaInfo['trustTemporary'] = $true", self.script)

    def test_documented_qa_trust_matches_msix_installer(self):
        docs = read(STORE_DOC)
        self.assertIn('Cert:\\LocalMachine\\TrustedPeople', docs)
        self.assertNotIn('Cert:\\CurrentUser\\TrustedPeople', docs)
        self.assertIn('Trusted Root Certification Authorities', docs)
        self.assertIn('elevated', docs)
        self.assertIn('Get-AppxPackage IgnacioSanguina.DenucziTV | Remove-AppxPackage', docs)

    def test_script_never_exports_or_passes_a_private_key(self):
        self.assertNotIn("Export-PfxCertificate", self.script)
        self.assertNotIn("New-RandomPassword", self.script)
        self.assertNotIn("$pfxPath", self.script)
        self.assertNotIn("sign /f ", self.script)
        self.assertNotIn(" /p $", self.script)
        self.assertIn("'certificate_path', 'certificate_password'", self.script)
        self.assertIn("msix_config must not contain $secretKey", self.script)

    def test_script_cleans_certificate_state_on_failure(self):
        finally_block = self.script.rsplit("} finally {", 1)[1]
        self.assertIn("Remove-TrustedPeopleCertificate -Certificate $trustedCertificate", finally_block)
        # Do not delete an existing trust entry when insertion failed.
        self.assertNotIn("Remove-TrustedPeopleCertificate -Certificate $qaCertificate", finally_block)
        self.assertIn("Remove-TrustedPeopleCertificate -Certificate $trustedCertificate", self.script)
        self.assertIn("-DeleteKey -Force", finally_block)
        self.assertIn("Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force", finally_block)
        self.assertIn("Copy-ReleaseCrt -Bundle $bundle -CrtPath $crtPath", finally_block)

    def test_script_verifies_bundle_and_package_integrity(self):
        for expected in (
            "Get-BundleProtectedSnapshot",
            "Assert-BundleUnchanged",
            "Assert-BundlePolicy",
            "Assert-ReleaseCrt",
            "Get-MsixPayloadHashes",
            "Assert-MsixPayloadMatches",
            "Assert-MsixCrtPayload",
            "Get-HashDictionaryDigest",
            "verifiedBeforeAndAfterPackaging = $true",
            "payloadMatched = $true",
            "runtimeMatchesOfficial = $true",
        ):
            self.assertIn(expected, self.script)
        self.assertGreaterEqual(
            self.script.count("Assert-BundleUnchanged -Bundle $bundle -Snapshot $bundleSnapshot"),
            1,
        )
        self.assertIn(
            "$bundleSnapshot = Get-BundleProtectedSnapshot -Bundle $bundle",
            self.script,
        )
        self.assertIn(
            "$storePayload = Get-MsixPayloadHashes -Path $storeMsix",
            self.script,
        )
        self.assertIn(
            "$qaPayload = Get-MsixPayloadHashes -Path $qaMsix",
            self.script,
        )
        self.assertNotIn("if ($name -match '^resources", self.script)
        self.assertIn(
            "$storeManifest.manifestSha256 -cne $qaManifest.manifestSha256",
            self.script,
        )

    def test_signing_metadata_is_not_compared_as_application_payload(self):
        # SignTool can add AppxSignature.p7x and a PE integrity catalog.
        # The original app, VC++ libraries, PRI files and assets must still match.
        self.assertIn("'AppxMetadata/CodeIntegrity.cat'", self.script)
        self.assertIn("$entry.FullName.Replace('\\', '/')", self.script)
        self.assertIn("'AppxSignature.p7x'", self.script)
        self.assertIn('Duplicate MSIX payload path:', self.script)
        self.assertIn('missing from QA:', self.script)
        self.assertIn('unexpected in QA:', self.script)
        self.assertIn('different content for:', self.script)
        self.assertIn('$qaPayload = Get-MsixPayloadHashes -Path $qaMsix', self.script)
        behavior = read(ROOT / 'test/packaging/test_msix_script.ps1')
        self.assertIn('AppxMetadata\\CodeIntegrity.cat', behavior)
        self.assertIn('AppxMetadata/Unexpected.cat', behavior)
        self.assertIn('unexpected.exe', behavior)
        self.assertIn("'resources.pri'] = 'modified resource index'", behavior)

    def test_manifest_visual_assets_allow_scale_variants_without_skipping_logo_checks(self):
        self.assertIn("Assert-MsixVisualAssets -Manifest $manifest -Entries $entries", self.script)
        self.assertIn("$logo = $Manifest.SelectSingleNode", self.script)
        self.assertIn("'Square44x44Logo', 'Square150x150Logo'", self.script)
        self.assertIn("$relative = $reference.Trim().Replace", self.script)
        self.assertIn("'Logo$'", self.script)
        self.assertIn("scale-\\d+", self.script)
        self.assertIn("missing the manifest image", self.script)
        self.assertNotIn("        'Images/StoreLogo.png'", self.script)

    def test_script_verifies_manifest_content_and_runtime_policy(self):
        for expected in (
            "AppxManifest.xml",
            "runFullTrust",
            "Windows.FullTrustApplication",
            "en-US",
            "es-ES",
            "dartjni.dll",
            "*.pdb",
            "vcruntime140.dll",
            "msvcp140.dll",
            "AppxSignature.p7x",
            "Get-AuthenticodeSignature",
            "Assert-PeX64",
        ):
            self.assertIn(expected, self.script)
        self.assertIn("$identity.ProcessorArchitecture -cne $architecture", self.script)
        self.assertIn("$identity.Version -cne $packageVersion", self.script)
        self.assertIn("manifestPublisher = $identity.Publisher", self.script)
        self.assertIn(
            "restrictedcapabilities", self.script
        )
        self.assertIn(
            "f:Capabilities/rescap:Capability[@Name=\"runFullTrust\"]", self.script
        )


class StorageAndChannelStaticTest(unittest.TestCase):
    def test_update_channel_is_compile_time_and_store_builds_skip_github(self):
        channel = read(ROOT / "lib/features/updates/domain/update_channel.dart")
        main = read(ROOT / "lib/main.dart")
        controls = read(
            ROOT / "lib/features/updates/presentation/software_update_controls.dart"
        )
        self.assertIn("bool.fromEnvironment('DENUCZI_STORE_BUILD')", channel)
        self.assertIn("UpdateChannel.microsoftStore", channel)
        self.assertIn("AppDistribution.usesGitHubUpdater", main)
        self.assertIn("ChangeNotifierProvider<UpdateController>", main)
        self.assertIn("storeManaged", controls)
        self.assertIn("updatesStoreManagedTitle", controls)

    def test_existing_storage_paths_are_not_redirected(self):
        repository = read(
            ROOT / "lib/features/personal_library/data/sqlite_library_repository.dart"
        )
        self.assertIn("library.sqlite", repository)
        self.assertIn("denuczi_tv", repository)
        self.assertNotIn("DENUCZI_STORE_BUILD", repository)
        self.assertNotIn("IgnacioSanguina", repository)


class DocumentationAndSecretsTest(unittest.TestCase):
    def test_store_documentation_covers_required_topics(self):
        text = read(STORE_DOC)
        for expected in (
            "1.6.3.0",
            "0.6.3",
            "IgnacioSanguina.DenucziTV",
            "CN=055E0D46-1999-438C-9CDB-4069928369ED",
            "runFullTrust",
            "WACK",
            "1366x768",
            "privacy",
            "package flight",
            "screenshots",
            "Partner Center",
        ):
            self.assertIn(expected, text)

    def test_privacy_policy_is_published_with_the_site(self):
        text = read(PRIVACY)
        self.assertIn("DenucziTV", text)
        self.assertIn("2026", text)
        self.assertIn("GitHub", text)
        self.assertIn("Microsoft Store", text)
        self.assertIn("local", text.lower())
        self.assertIn("privacy.html", read(ROOT / "docs/index.html"))
        self.assertIn("docs/MICROSOFT_STORE.md", read(ROOT / "README.md"))
        self.assertIn("MICROSOFT_STORE.md", read(ROOT / "docs/WINDOWS_PACKAGING.md"))

    def test_repository_has_no_private_key_material(self):
        forbidden_extensions = {".pfx", ".p12", ".pem", ".key"}
        forbidden_headers = re.compile(
            r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|"
            r"-----BEGIN CERTIFICATE-----"
        )
        ignored = {".git", "build", ".dart_tool", "dist", "__pycache__", "demo"}
        current_test = Path(__file__).resolve()
        for path in ROOT.rglob("*"):
            if not path.is_file() or path.resolve() == current_test:
                continue
            if any(part in ignored for part in path.parts):
                continue
            self.assertNotIn(path.suffix.lower(), forbidden_extensions, path)
            if path.stat().st_size > 2_000_000:
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            self.assertIsNone(forbidden_headers.search(text), path)


if __name__ == "__main__":
    unittest.main()
