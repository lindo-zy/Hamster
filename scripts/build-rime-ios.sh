#!/usr/bin/env bash
# Rebuild the original Rime 1.9.0 engines; the old release was removed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/.build/rime-ios"
PREFIX="$WORK/install"
SOURCES_ONLY=false
if [[ "${1:-}" == --sources-only ]]; then SOURCES_ONLY=true; shift; fi
[[ $# -eq 0 ]] || { echo "Usage: $0 [--sources-only]" >&2; exit 2; }
mkdir -p "$WORK" "$PREFIX" "$ROOT/Frameworks"
JOBS="${RIME_BUILD_JOBS:-$(sysctl -n hw.ncpu)}"

fetch_source() {
  local name="$1" repository="$2" revision="$3"
  if [[ ! -d "$WORK/$name/.git" ]]; then
    git init -q "$WORK/$name"
    git -C "$WORK/$name" remote add origin "$repository"
  fi
  if ! git -C "$WORK/$name" cat-file -e "$revision^{commit}" 2>/dev/null; then
    git -C "$WORK/$name" fetch --depth 1 origin "$revision"
  fi
  git -C "$WORK/$name" checkout -q --detach "$revision"
}

# Both engines use exactly the same dependency revisions in their submodules.
fetch_source librime https://github.com/rime/librime.git a60876745af20ecc8489ec6997c6c195949b99ac
fetch_source librime-sbxlm https://github.com/sbxlmdsl/librime.git 2e5e293fedbbf7b7e04fbf75e1c2824eeca42dd0
git -C "$WORK/librime" submodule update --init --depth 1 \
  deps/glog deps/leveldb deps/marisa-trie deps/opencc deps/yaml-cpp
fetch_source lua https://github.com/imfuxiao/librime-lua.git 7c297e4d2e08fcdd3e9b2dcae2a42317b9a217ff
fetch_source lua/thirdparty https://github.com/hchunhui/librime-lua.git 9c53b362229766a97b83683b9541c46679118a90

BOOST_ARCHIVE="$WORK/boost_1_82_0.tar.bz2"
BOOST_SHA=a6e1ab9b0860e6a2881dd7b21fe9f737a095e5f33a3a874afc6a345228597ee6
if [[ ! -f "$BOOST_ARCHIVE" ]]; then
  curl -fL --retry 3 --connect-timeout 30 \
    https://archives.boost.io/release/1.82.0/source/boost_1_82_0.tar.bz2 -o "$BOOST_ARCHIVE.part"
  mv "$BOOST_ARCHIVE.part" "$BOOST_ARCHIVE"
fi
echo "$BOOST_SHA  $BOOST_ARCHIVE" | shasum -a 256 -c -
if [[ ! -d "$WORK/boost_1_82_0" ]]; then tar -xjf "$BOOST_ARCHIVE" -C "$WORK"; fi
if [[ "$SOURCES_ONLY" == true ]]; then
  echo "Pinned Rime, Shengbi, Lua, and Boost sources are ready in $WORK"
  exit 0
fi
command -v cmake >/dev/null || { echo "Install CMake: brew install cmake" >&2; exit 1; }
SDK="${RIME_IOS_SDK_PATH:-$(xcrun --sdk iphoneos --show-sdk-path)}"
[[ -d "$SDK" ]] || { echo "iPhoneOS SDK not found: $SDK" >&2; exit 1; }
CLANG="$(xcrun --find clang)"
CLANGXX="$(xcrun --find clang++)"

# Build Boost without CocoaPods, ICU or an Apple account.
BOOST="$WORK/boost_1_82_0"
cat > "$WORK/boost-ios-clang" <<EOF
#!/bin/sh
exec "$CLANGXX" -target arm64-apple-ios16.0 -isysroot "$SDK" "\$@"
EOF
chmod +x "$WORK/boost-ios-clang"
cat > "$WORK/boost-user-config.jam" <<EOF
using clang : ios : "$WORK/boost-ios-clang" ;
EOF
(
  cd "$BOOST"
  [[ -x ./b2 ]] || ./bootstrap.sh --with-libraries=atomic,filesystem,regex,system
  ./b2 --user-config="$WORK/boost-user-config.jam" toolset=clang-ios \
    target-os=iphone architecture=arm address-model=64 abi=aapcs binary-format=mach-o \
    variant=release link=static threading=multi cxxstd=14 \
    --with-atomic --with-filesystem --with-regex --with-system \
    --stagedir="$WORK/boost-stage" -j"$JOBS" stage
)
CMAKE_FLAGS=(
  -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$SDK"
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0
  -DCMAKE_C_COMPILER="$CLANG" -DCMAKE_CXX_COMPILER="$CLANGXX"
  -DCMAKE_C_COMPILER_TARGET=arm64-apple-ios16.0
  -DCMAKE_CXX_COMPILER_TARGET=arm64-apple-ios16.0
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib
  -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH="$PREFIX"
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
  -DBUILD_SHARED_LIBS=OFF -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
)
build_dependency() {
  local name="$1" source="$2"; shift 2
  cmake -S "$source" -B "$WORK/build-$name" "${CMAKE_FLAGS[@]}" "$@"
  cmake --build "$WORK/build-$name" --parallel "$JOBS"
  cmake --install "$WORK/build-$name"
}
DEPS="$WORK/librime/deps"
build_dependency glog "$DEPS/glog" -DBUILD_TESTING=OFF -DWITH_GFLAGS=OFF
build_dependency leveldb "$DEPS/leveldb" -DLEVELDB_BUILD_TESTS=OFF -DLEVELDB_BUILD_BENCHMARKS=OFF -DHAVE_SNAPPY=OFF -DHAVE_CRC32C=OFF -DHAVE_TCMALLOC=OFF
build_dependency marisa "$DEPS"
build_dependency yaml-cpp "$DEPS/yaml-cpp" -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF -DYAML_CPP_BUILD_CONTRIB=OFF

# OpenCC's data generators are host tools: only cross-compile its library.
python3 - "$DEPS/opencc" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1])
for relative, target in (("src/CMakeLists.txt", "tools"), ("CMakeLists.txt", "data")):
    path = source / relative
    path.write_text(path.read_text().replace(f"add_subdirectory({target})", "# Host tools and data excluded from the iOS library build."))
PY
cmake -S "$DEPS/opencc" -B "$WORK/build-opencc" "${CMAKE_FLAGS[@]}" \
  -DENABLE_GTEST=OFF -DENABLE_BENCHMARK=OFF -DBUILD_DOCUMENTATION=OFF
cmake --build "$WORK/build-opencc" --target libopencc --parallel "$JOBS"
cp "$WORK/build-opencc/src/libopencc.a" "$PREFIX/lib/libopencc.a"
mkdir -p "$PREFIX/include/opencc"
cp "$DEPS/opencc/src/"*.hpp "$DEPS/opencc/src/"*.h "$WORK/build-opencc/src/"*.h "$PREFIX/include/opencc/"

for variant in librime librime-sbxlm; do
  python3 "$ROOT/scripts/prepare-rime-source.py" "$WORK/$variant" "$WORK/lua"
  cmake -S "$WORK/$variant" -B "$WORK/build-$variant" "${CMAKE_FLAGS[@]}" \
    -DBUILD_STATIC=ON -DBUILD_TEST=OFF -DBUILD_MERGED_PLUGINS=ON \
    -DBUILD_SEPARATE_LIBS=OFF -DENABLE_EXTERNAL_PLUGINS=OFF \
    -DBoost_NO_BOOST_CMAKE=ON -DBoost_NO_SYSTEM_PATHS=ON \
    -DBOOST_ROOT="$BOOST" -DBOOST_LIBRARYDIR="$WORK/boost-stage/lib" \
    -DBoost_INCLUDE_DIR="$BOOST" \
    -DBoost_FILESYSTEM_LIBRARY_RELEASE="$WORK/boost-stage/lib/libboost_filesystem.a" \
    -DBoost_REGEX_LIBRARY_RELEASE="$WORK/boost-stage/lib/libboost_regex.a" \
    -DBoost_SYSTEM_LIBRARY_RELEASE="$WORK/boost-stage/lib/libboost_system.a" \
    -DMarisa_INCLUDE_PATH="$PREFIX/include" -DMarisa_LIBRARY="$PREFIX/lib/libmarisa.a"
  cmake --build "$WORK/build-$variant" --target rime-static --parallel "$JOBS"
done
# Link checks catch missing dependencies and static Lua registration; no device execution.
cat > "$WORK/link-check.c" <<'EOF'
extern void *rime_get_api(void);
int main(void) { return rime_get_api() == 0; }
EOF
for variant in librime librime-sbxlm; do
  "$CLANG" -target arm64-apple-ios16.0 -isysroot "$SDK" "$WORK/link-check.c" \
    "$WORK/build-$variant/lib/librime.a" "$PREFIX/lib/"*.a "$WORK/boost-stage/lib/"*.a \
    -lc++ -liconv -o "$WORK/link-check-$variant"
done
python3 "$ROOT/scripts/create-rime-xcframeworks.py" "$WORK"
