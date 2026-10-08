#!/usr/bin/env bash
# Build a device archive without an Apple certificate, then package for TrollStore.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/artifacts/trollstore"
APP_PATH=""
PREPARE_ONLY=false
SKIP_DEPENDENCIES=false
IOS_VERSION=16

usage() {
  cat <<'EOF'
Usage: ./build-tipa.sh [options]
  --ios-version VER    Minimum iOS version: 16, 17, or all (default: 16)
  --output-dir DIR     Output directory (default: artifacts/trollstore)
  --prepare-only       Prepare Rime frameworks and bundled input schemas only
  --skip-dependencies  Use dependencies already present in the checkout
  --app PATH          Package an existing Hamster.app for the selected iOS version
  -h, --help          Show this help

Requires macOS and full Xcode for compilation. No Apple ID, signing certificate,
provisioning profile, or GitHub signing secrets are required.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir|--app|--ios-version)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { echo "Missing value for $1" >&2; exit 2; }
      case "$1" in
        --app) APP_PATH="$2" ;;
        --output-dir) OUTPUT_DIR="$2" ;;
        --ios-version) IOS_VERSION="$2" ;;
      esac
      shift 2 ;;
    --prepare-only) PREPARE_ONLY=true; shift ;;
    --skip-dependencies) SKIP_DEPENDENCIES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$IOS_VERSION" in
  16|17|all) ;;
  *) echo "--ios-version must be 16, 17, or all" >&2; exit 2 ;;
esac
if [[ -n "$APP_PATH" && "$PREPARE_ONLY" == true ]]; then
  echo "--app and --prepare-only cannot be combined" >&2
  exit 2
fi
if [[ -n "$APP_PATH" && "$IOS_VERSION" == all ]]; then
  echo "--app requires a single --ios-version (16 or 17)" >&2
  exit 2
fi
[[ "$(uname -s)" == Darwin ]] || { echo "This build requires macOS." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Install Python 3 first." >&2; exit 1; }

# Resolve user-supplied paths before changing directory.
OUTPUT_DIR="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$OUTPUT_DIR")"
if [[ -n "$APP_PATH" ]]; then
  [[ -d "$APP_PATH" ]] || { echo "App does not exist: $APP_PATH" >&2; exit 1; }
  APP_PATH="$(cd "$APP_PATH" && pwd)"
fi
cd "$PROJECT_ROOT"

if [[ -z "$APP_PATH" ]]; then
  if [[ "$PREPARE_ONLY" != true ]]; then
    xcodebuild -version || { echo "Select a full Xcode installation using DEVELOPER_DIR or xcode-select." >&2; exit 1; }
    xcrun --sdk iphoneos --show-sdk-path >/dev/null
  fi
  if [[ "$SKIP_DEPENDENCIES" != true ]]; then
    bash "$PROJECT_ROOT/librimeFramework.sh"
    bash "$PROJECT_ROOT/InputSchemaBuild.sh"
  fi
  python3 "$PROJECT_ROOT/scripts/validate-dependencies.py"
  if [[ "$PREPARE_ONLY" == true ]]; then exit 0; fi

  if [[ "$IOS_VERSION" == all ]]; then
    for target in 16 17; do
      bash "$PROJECT_ROOT/build-tipa.sh" --ios-version "$target" \
        --skip-dependencies --output-dir "$OUTPUT_DIR"
    done
    exit 0
  fi
  mkdir -p "$PROJECT_ROOT/.build/trollstore"
  BUILD_DIR="$(mktemp -d "$PROJECT_ROOT/.build/trollstore/build.XXXXXX")"
  # Keep the archive and log on failure to make CI diagnostics useful.
  echo "Build directory: $BUILD_DIR"
  xcodebuild archive \
    -project "$PROJECT_ROOT/Hamster.xcodeproj" \
    -scheme Hamster \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -sdk iphoneos \
    -archivePath "$BUILD_DIR/Hamster-ios$IOS_VERSION.xcarchive" \
    -derivedDataPath "$PROJECT_ROOT/.build/trollstore/DerivedData-ios$IOS_VERSION" \
    -clonedSourcePackagesDirPath "$PROJECT_ROOT/.build/trollstore/SourcePackages" \
    -onlyUsePackageVersionsFromResolvedFile \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    IPHONEOS_DEPLOYMENT_TARGET="$IOS_VERSION.0" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= \
    PROVISIONING_PROFILE_SPECIFIER= \
    2>&1 | tee "$BUILD_DIR/xcodebuild.log"
  APP_PATH="$BUILD_DIR/Hamster-ios$IOS_VERSION.xcarchive/Products/Applications/Hamster.app"
fi

python3 "$PROJECT_ROOT/scripts/package-tipa.py" --app "$APP_PATH" \
  --ios-version "$IOS_VERSION" --output-dir "$OUTPUT_DIR"
