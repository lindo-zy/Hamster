"""Exercise real ad-hoc signing and ZIP packaging with minimal iOS binaries.

These fixtures validate the packaging path; they are not Hamster builds.
"""
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("tipa", ROOT / "scripts/package-tipa.py")
tipa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tipa)


class PackagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace = tempfile.TemporaryDirectory(prefix="hamster-packaging-tests-")
        cls.directory = Path(cls.workspace.name)
        sdk = os.environ.get("RIME_IOS_SDK_PATH")
        if not sdk:
            sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
        source = cls.directory / "main.c"
        source.write_text("int main(void) { return 0; }\n")
        cls.binary = cls.directory / "binary"
        subprocess.run(["xcrun", "clang", "-target", "arm64-apple-ios16.0", "-isysroot", sdk, str(source), "-o", str(cls.binary)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.workspace.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=self.directory)
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / "Hamster.app"
        self.output = Path(self.temp.name) / "output with spaces"
        self.create_bundle(self.app, tipa.APP_ID)
        for name in tipa.EXTENSIONS:
            self.create_bundle(self.app / "PlugIns" / (name + ".appex"), tipa.APP_ID + "." + name)
        for name in ("SharedSupport.zip", "rime-ice.zip"):
            with zipfile.ZipFile(self.app / name, "w") as archive:
                archive.writestr("fixture.yaml", "schema: fixture\n")

    def create_bundle(self, path, identifier):
        path.mkdir(parents=True)
        executable = path.stem
        import shutil
        shutil.copy2(self.binary, path / executable)
        info = {"CFBundleIdentifier": identifier, "CFBundleExecutable": executable,
                "CFBundlePackageType": "XPC!" if path.suffix == ".appex" else "APPL",
                "MinimumOSVersion": "16.0", "CFBundleSupportedPlatforms": ["iPhoneOS"],
                "CFBundleVersion": "1", "CFBundleShortVersionString": "3.0.0"}
        if path.suffix == ".appex":
            info["NSExtension"] = {"NSExtensionPointIdentifier": "com.apple.keyboard-service", "NSExtensionPrincipalClass": "Fixture"}
        with (path / "Info.plist").open("wb") as file:
            plistlib.dump(info, file)
        (path / "embedded.mobileprovision").write_text("fixture profile")

    def test_signed_package_preserves_all_groups_and_removes_profiles(self):
        tipa.package(self.app, self.output)
        artifact = next(self.output.glob("*.tipa"))
        self.assertTrue(artifact.with_suffix(".tipa.sha256").is_file())
        with zipfile.ZipFile(artifact) as archive:
            self.assertIsNone(archive.testzip())
            self.assertFalse(any(name.endswith("embedded.mobileprovision") for name in archive.namelist()))
            archive.extractall(Path(self.temp.name) / "extracted")
        extracted = Path(self.temp.name) / "extracted/Payload/Hamster.app"
        for bundle in (extracted, *(extracted / "PlugIns" / (name + ".appex") for name in tipa.EXTENSIONS)):
            result = subprocess.run(["/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(bundle)], check=True, capture_output=True)
            entitlements = plistlib.loads(result.stdout)
            self.assertEqual(entitlements["com.apple.security.application-groups"], [tipa.GROUP])
            self.assertFalse(entitlements["get-task-allow"])
            self.assertTrue((self.app / "embedded.mobileprovision").exists())

    def test_rejects_missing_keyboard(self):
        import shutil
        shutil.rmtree(self.app / "PlugIns/SbxlmKeyboard.appex")
        with self.assertRaisesRegex(ValueError, "Both keyboard"):
            tipa.package(self.app, self.output)

    def test_rejects_higher_minimum_ios(self):
        path = self.app / "Info.plist"
        info = tipa.read_plist(path)
        info["MinimumOSVersion"] = "17.0"
        with path.open("wb") as file:
            plistlib.dump(info, file)
        with self.assertRaisesRegex(ValueError, "iOS 16.0"):
            tipa.package(self.app, self.output)

    def test_rejects_wrong_bundle_id(self):
        path = self.app / "PlugIns/HamsterKeyboard.appex/Info.plist"
        info = tipa.read_plist(path)
        info["CFBundleIdentifier"] = "wrong.keyboard"
        with path.open("wb") as file:
            plistlib.dump(info, file)
        with self.assertRaisesRegex(ValueError, "Unexpected bundle ID"):
            tipa.package(self.app, self.output)

    def test_rejects_corrupt_schema(self):
        (self.app / "rime-ice.zip").write_text("not a ZIP")
        with self.assertRaises(zipfile.BadZipFile):
            tipa.package(self.app, self.output)

    def test_rejects_non_executable_binary(self):
        (self.app / "Hamster").chmod(0o644)
        with self.assertRaisesRegex(ValueError, "permission"):
            tipa.package(self.app, self.output)

    def test_rejects_output_inside_original_app(self):
        with self.assertRaisesRegex(ValueError, "outside the original App"):
            tipa.package(self.app, self.app / "output")
        self.assertFalse((self.app / "output").exists())

    def test_build_script_packages_relative_paths_without_xcode(self):
        result = subprocess.run(
            ["bash", str(ROOT / "build-tipa.sh"), "--app", "Hamster.app", "--output-dir", "CLI output"],
            cwd=self.temp.name, check=True, capture_output=True, text=True,
        )
        self.assertIn("TrollStore package:", result.stdout)
        self.assertEqual(len(list((Path(self.temp.name) / "CLI output").glob("*.tipa"))), 1)
