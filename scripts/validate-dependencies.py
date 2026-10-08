#!/usr/bin/env python3
"""Fail early when a required framework or input schema is missing/invalid."""
from pathlib import Path
import hashlib
import json
import plistlib
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FRAMEWORKS = ("librime", "librime-sbxlm", "boost_atomic", "boost_filesystem", "boost_regex", "boost_system", "libglog", "libleveldb", "libmarisa", "libopencc", "libyaml-cpp")


def validate_frameworks():
    manifest_path = ROOT / "Frameworks/trollstore-build.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.is_file() else None
    if manifest:
        for name in ("build-rime-ios.sh", "prepare-rime-source.py", "create-rime-xcframeworks.py", "validate-dependencies.py"):
            assert manifest.get("build_scripts", {}).get(name) == hashlib.sha256((ROOT / "scripts" / name).read_bytes()).hexdigest(), "Rime build scripts changed; rebuild the frameworks."
    for name in FRAMEWORKS:
        framework = ROOT / "Frameworks" / (name + ".xcframework")
        with (framework / "Info.plist").open("rb") as file:
            info = plistlib.load(file)
        slices = [item for item in info["AvailableLibraries"] if item["SupportedPlatform"] == "ios" and not item.get("SupportedPlatformVariant") and "arm64" in item["SupportedArchitectures"]]
        assert len(slices) == 1, f"Missing arm64 iOS slice: {framework}"
        item = slices[0]
        library = framework / item["LibraryIdentifier"] / item["LibraryPath"]
        assert library.is_file(), f"Missing static library: {library}"
        if manifest:
            assert hashlib.sha256(library.read_bytes()).hexdigest() == manifest["libraries"][name], f"Framework checksum mismatch: {name}"
        assert "arm64" in subprocess.check_output(["/usr/bin/lipo", "-archs", str(library)], text=True).split()


def validate_schemas():
    for name, required in (("SharedSupport.zip", "hamster.yaml"), ("rime-ice.zip", "rime_ice.schema.yaml")):
        with zipfile.ZipFile(ROOT / "Resources/SharedSupport" / name) as archive:
            assert archive.testzip() is None, f"Corrupt schema ZIP: {name}"
            assert required in archive.namelist(), f"Missing {required} in {name}"


if __name__ == "__main__":
    try:
        validate_frameworks()
        if "--frameworks-only" not in sys.argv:
            validate_schemas()
    except (OSError, KeyError, ValueError, AssertionError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        sys.exit(f"Dependency validation failed: {error}")
    print("Rime dependencies validated.")
