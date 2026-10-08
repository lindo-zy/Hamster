#!/usr/bin/env python3
"""Wrap the arm64 static libraries in device-only XCFrameworks."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
work = Path(sys.argv[1])
libraries = {name: work / ("build-" + name + "/lib/librime.a") for name in ("librime", "librime-sbxlm")}
for name in ("atomic", "filesystem", "regex", "system"):
    libraries["boost_" + name] = work / ("boost-stage/lib/libboost_" + name + ".a")
for name in ("glog", "leveldb", "marisa", "opencc", "yaml-cpp"):
    libraries["lib" + name] = work / ("install/lib/lib" + name + ".a")
manifest = {"minimum_ios": "16.0", "engines": {}, "libraries": {}}
manifest["build_scripts"] = {name: hashlib.sha256((root / "scripts" / name).read_bytes()).hexdigest() for name in ("build-rime-ios.sh", "prepare-rime-source.py", "rime-hamster.patch", "create-rime-xcframeworks.py", "validate-dependencies.py")}
for variant in ("librime", "librime-sbxlm", "lua"):
    manifest["engines"][variant] = subprocess.check_output(["git", "-C", str(work / variant), "rev-parse", "HEAD"], text=True).strip()
for name, library in libraries.items():
    assert library.is_file(), f"Missing library: {library}"
    assert subprocess.check_output(["/usr/bin/lipo", "-archs", str(library)], text=True).strip() == "arm64"
    framework = root / "Frameworks" / (name + ".xcframework")
    if framework.exists():
        shutil.rmtree(framework)
    (framework / "ios-arm64").mkdir(parents=True)
    filename = name + ".a"
    shutil.copyfile(library, framework / "ios-arm64" / filename)
    info = {"CFBundlePackageType": "XFWK", "XCFrameworkFormatVersion": "1.0", "AvailableLibraries": [{"LibraryIdentifier": "ios-arm64", "LibraryPath": filename, "SupportedArchitectures": ["arm64"], "SupportedPlatform": "ios"}]}
    with (framework / "Info.plist").open("wb") as file:
        plistlib.dump(info, file)
    manifest["libraries"][name] = hashlib.sha256(library.read_bytes()).hexdigest()
(root / "Frameworks/trollstore-build.json").write_text(json.dumps(manifest, indent=2) + "\n")
print("Built device arm64 XCFrameworks for both Rime 1.9.0 engines.")
