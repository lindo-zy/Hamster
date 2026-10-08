#!/usr/bin/env bash
# Prepare the Rime 1.9-compatible bundled schemas, from fixed source revisions.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="$ROOT/Resources/SharedSupport"
SCHEMA_HASH="$(shasum -a 256 "$ROOT/InputSchemaBuild.sh" "$OUTPUT/hamster.yaml" | awk '{print $1}' | shasum -a 256 | awk '{print $1}')"
if [[ -f "$OUTPUT/trollstore-schema-build.sha256" ]] && [[ "$(cat "$OUTPUT/trollstore-schema-build.sha256")" == "$SCHEMA_HASH" ]] && python3 - "$OUTPUT" <<'CHECK'
from pathlib import Path
import sys, zipfile
try:
    for name, required in (("SharedSupport.zip", "hamster.yaml"), ("rime-ice.zip", "rime_ice.schema.yaml")):
        with zipfile.ZipFile(Path(sys.argv[1]) / name) as archive:
            assert archive.testzip() is None and required in archive.namelist()
except (OSError, AssertionError, zipfile.BadZipFile):
    sys.exit(1)
CHECK
then
  echo "Using existing bundled schemas."
  exit 0
fi
mkdir -p "$ROOT/.build" "$ROOT/.deps" "$OUTPUT"
WORK="$(mktemp -d "$ROOT/.build/schema.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fetch_source() {
  local name="$1" repository="$2" revision="$3"
  git init -q "$WORK/$name"
  git -C "$WORK/$name" remote add origin "$repository"
  git -C "$WORK/$name" fetch --depth 1 origin "$revision"
  git -C "$WORK/$name" checkout -q --detach FETCH_HEAD
}
# This published archive supplies OpenCC's dictionaries and its macOS host tool.
if [[ ! -f "$ROOT/.deps/share/opencc/t2s.json" ]]; then
  curl -fL --retry 3 --connect-timeout 30 \
    https://github.com/rime/librime/releases/download/1.8.5/rime-deps-08dd95f-macOS.tar.bz2 \
    -o "$WORK/rime-deps.tar.bz2"
  tar -xjf "$WORK/rime-deps.tar.bz2" -C "$ROOT/.deps"
fi
OPENCC="${OPENCC_BINARY:-$(command -v opencc || true)}"
if [[ -z "$OPENCC" ]]; then OPENCC="$ROOT/.deps/bin/opencc"; fi
"$OPENCC" --version
fetch_source prelude https://github.com/rime/rime-prelude.git ad742b87cf9a902287146ee3d3cdba2033f8b835
fetch_source essay https://github.com/rime/rime-essay.git e0519d0579722a0871efb68189272cba61a7350b
fetch_source ice https://github.com/iDvel/rime-ice.git db2375b0d9dba21247da4e5dd58c3d36c56c2b5a
mkdir -p "$WORK/SharedSupport/opencc"
cp -R "$ROOT/.deps/share/opencc/." "$WORK/SharedSupport/opencc/"
cp "$WORK/prelude/"*.yaml "$WORK/SharedSupport/"
cp "$WORK/essay/essay.txt" "$WORK/SharedSupport/"
cp "$OUTPUT/hamster.yaml" "$WORK/SharedSupport/"
# Match the project's original minimal default schema list.
sed -e '/- schema:/d' \
  -e 's/^config_version: \(["]*\)\([0-9.]*\)\(["]*\)$/config_version: \1\2.minimal\3/' \
  "$WORK/SharedSupport/default.yaml" > "$WORK/default.yaml"
mv "$WORK/default.yaml" "$WORK/SharedSupport/default.yaml"
curl -fL --retry 3 --connect-timeout 30 \
  https://github.com/rime/rime-emoji/archive/refs/tags/15.0.zip -o "$WORK/emoji.zip"
unzip -q "$WORK/emoji.zip" -d "$WORK"
for target in category word; do
  "$OPENCC" -c "$ROOT/.deps/share/opencc/t2s.json" \
    -i "$WORK/rime-emoji-15.0/opencc/emoji_$target.txt" > "$WORK/$target.txt"
  sed -i '' 's/鼔/鼓/g' "$WORK/$target.txt"
  cat "$WORK/$target.txt" "$WORK/rime-emoji-15.0/opencc/emoji_$target.txt" \
    | awk '!seen[$1]++' > "$WORK/SharedSupport/opencc/emoji_$target.txt"
done
cp "$WORK/rime-emoji-15.0/opencc/emoji.json" "$WORK/SharedSupport/opencc/"
python3 - "$WORK" "$OUTPUT" <<'ZIP'
from pathlib import Path
import sys, zipfile
work, output = map(Path, sys.argv[1:])
for source, name in ((work / "SharedSupport", "SharedSupport.zip"), (work / "ice", "rime-ice.zip")):
    with zipfile.ZipFile(work / name, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(source.rglob("*")):
            relative = path.relative_to(source)
            if path.is_file() and ".git" not in relative.parts and ".github" not in relative.parts:
                archive.write(path, relative.as_posix())
    (work / name).replace(output / name)
ZIP
echo "$SCHEMA_HASH" > "$OUTPUT/trollstore-schema-build.sha256"
