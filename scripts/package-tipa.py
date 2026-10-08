#!/usr/bin/env python3
"""Validate, ad-hoc sign, and zip Hamster with both keyboard extensions."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
APP_ID = "dev.fuxiao.app.Hamster"
GROUP = "group.dev.fuxiao.app.Hamster"
EXTENSIONS = ("HamsterKeyboard", "SbxlmKeyboard")


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], stderr=subprocess.STDOUT).decode()


def read_plist(path):
    with path.open("rb") as file:
        return plistlib.load(file)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_binary(binary, minimum_ios="16.0", exact=False):
    require(binary.is_file(), f"Missing executable: {binary}")
    require(os.access(binary, os.X_OK), f"Executable permission missing: {binary}")
    require(run("/usr/bin/lipo", "-archs", binary).strip() == "arm64", f"Expected device arm64 binary: {binary}")
    commands = run("/usr/bin/otool", "-l", binary)
    version = re.search(r"cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform (\d+)\s+minos ([\d.]+)", commands)
    if version:
        require(version[1] == "2", f"Not an iOS device binary: {binary}")
        minimum = version[2]
    else:
        version = re.search(r"cmd LC_VERSION_MIN_IPHONEOS\s+cmdsize \d+\s+version ([\d.]+)", commands)
        require(version is not None, f"Missing iOS deployment target: {binary}")
        minimum = version[1]
    parts = tuple(int(part) for part in minimum.split("."))
    actual = parts + (0,) * (3 - len(parts))
    expected = tuple(int(part) for part in minimum_ios.split(".")) + (0,)
    if exact:
        require(actual == expected, f"Binary must target iOS {minimum_ios}, found {minimum}: {binary}")
    else:
        require(actual <= expected, f"Binary requires iOS {minimum}: {binary}")


def validate_bundle(bundle, expected_id, minimum_ios="16.0"):
    info = read_plist(bundle / "Info.plist")
    require(info["CFBundleIdentifier"] == expected_id, f"Unexpected bundle ID in {bundle}")
    require(info.get("MinimumOSVersion") == minimum_ios, f"{bundle.name} must target iOS {minimum_ios}")
    require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], f"Not an iOS device bundle: {bundle}")
    executable = info["CFBundleExecutable"]
    require(Path(executable).name == executable, f"Invalid executable name in {bundle}")
    validate_binary(bundle / executable, minimum_ios, exact=True)
    if bundle.suffix == ".appex":
        require(info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.keyboard-service", f"Not a keyboard extension: {bundle}")
    return info


def sign_bundle(bundle, source_entitlements, entitlements_dir):
    info = read_plist(bundle / "Info.plist")
    entitlements = read_plist(source_entitlements)
    require(entitlements.get("com.apple.security.application-groups") == [GROUP], f"Missing shared App Group: {bundle}")
    # A local ad-hoc identity is sufficient. TrollStore applies CoreTrust signing
    # on the device and preserves these entitlements. Never enable get-task-allow.
    entitlements.update({
        "application-identifier": "TROLLTROLL." + info["CFBundleIdentifier"],
        "com.apple.developer.team-identifier": "TROLLTROLL",
        "keychain-access-groups": ["TROLLTROLL." + info["CFBundleIdentifier"]],
        "get-task-allow": False,
    })
    entitlement_file = entitlements_dir / (bundle.stem + ".plist")
    with entitlement_file.open("wb") as file:
        plistlib.dump(entitlements, file)
    run("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none",
        "--generate-entitlement-der", "--entitlements", entitlement_file, bundle)
    # codesign writes diagnostics to stderr and the entitlement plist to stdout.
    result = subprocess.run(["/usr/bin/codesign", "--display", "--entitlements", "-", "--xml", str(bundle)], check=True, capture_output=True)
    actual = plistlib.loads(result.stdout)
    require(actual == entitlements, f"Entitlements did not survive signing: {bundle}")
    run("/usr/bin/codesign", "--verify", "--strict", bundle)


def package(app, output_dir, minimum_ios="16.0"):
    require(minimum_ios in ("16.0", "17.0"), "Minimum iOS version must be 16.0 or 17.0")
    app = app.resolve()
    output_dir = output_dir.resolve()
    require(output_dir != app and app not in output_dir.parents, "Output directory must be outside the original App")
    require(app.name == "Hamster.app", "Expected Hamster.app")
    info = validate_bundle(app, APP_ID, minimum_ios)
    require({path.name for path in (app / "PlugIns").glob("*.appex")} == {name + ".appex" for name in EXTENSIONS}, "Both keyboard extensions must be embedded")
    for name in EXTENSIONS:
        validate_bundle(app / "PlugIns" / (name + ".appex"), APP_ID + "." + name, minimum_ios)
    for name, required in (("SharedSupport.zip", "hamster.yaml"), ("rime-ice.zip", "rime_ice.schema.yaml")):
        with zipfile.ZipFile(app / "SharedSupport" / name) as archive:
            require(archive.testzip() is None and archive.namelist(), f"Invalid bundled schema archive: {name}")
            require(required in archive.namelist(), f"Missing {required} in bundled schema archive: {name}")
    version = str(info["CFBundleShortVersionString"])
    build = str(info["CFBundleVersion"])
    require(re.fullmatch(r"[0-9A-Za-z._-]+", version + "-" + build), "Invalid version for output filename")
    output_dir.mkdir(parents=True, exist_ok=True)
    filename = f"Hamster-{version}-{build}-ios{minimum_ios.split('.')[0]}-arm64.tipa"
    destination = output_dir / filename
    with tempfile.TemporaryDirectory(prefix="hamster-tipa-") as staging:
        staging = Path(staging)
        payload = staging / "Payload"
        payload.mkdir()
        copied_app = payload / app.name
        shutil.copytree(app, copied_app, symlinks=True)
        for path in copied_app.rglob("*"):
            if path.name in ("embedded.mobileprovision", ".DS_Store") and path.is_file():
                path.unlink()
        # Sign all embedded code from the inside out, without --deep or a certificate.
        nested = sorted((p for p in copied_app.rglob("*") if p.suffix in (".framework", ".dylib")), key=lambda p: len(p.parts), reverse=True)
        for path in nested:
            if path.suffix == ".dylib":
                validate_binary(path, minimum_ios)
            else:
                framework_info = read_plist(path / "Info.plist")
                validate_binary(path / framework_info["CFBundleExecutable"], minimum_ios)
            run("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", path)
        for name in EXTENSIONS:
            sign_bundle(copied_app / "PlugIns" / (name + ".appex"), ROOT / name / (name + ".entitlements"), staging)
        sign_bundle(copied_app, ROOT / "Hamster/Hamster.entitlements", staging)
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", copied_app)
        temporary_tipa = staging / filename
        subprocess.run(["/usr/bin/zip", "-qry", str(temporary_tipa), "Payload"], cwd=staging, check=True)
        with zipfile.ZipFile(temporary_tipa) as archive:
            require(archive.testzip() is None, "Invalid tipa ZIP")
            require(all(name.startswith("Payload/") for name in archive.namelist()), "Invalid tipa layout")
            require(not any(name.endswith("embedded.mobileprovision") for name in archive.namelist()), "Provisioning profile in tipa")
        shutil.copyfile(temporary_tipa, destination)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    (output_dir / (filename + ".sha256")).write_text(f"{digest}  {filename}\n")
    print(f"TrollStore package: {destination}\nSHA256: {digest}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--ios-version", choices=("16", "17"), default="16")
    args = parser.parse_args()
    try:
        package(args.app, args.output_dir.resolve(), args.ios_version + ".0")
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        detail = error.output.decode(errors="replace") if isinstance(error, subprocess.CalledProcessError) and error.output else ""
        parser.exit(1, f"Packaging failed: {error}\n{detail}")
