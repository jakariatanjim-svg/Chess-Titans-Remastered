#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: bash tools/build_windows.sh VERSION}"
OUTPUT_DIR="build"
PACKAGE_DIR="$OUTPUT_DIR/package"
EXECUTABLE="$OUTPUT_DIR/Chess-Titans-Remastered.exe"
ARCHIVE="$OUTPUT_DIR/Chess-Titans-Remastered-v${VERSION}-Windows-x64.zip"

mkdir -p "$PACKAGE_DIR"
rm -f "$PACKAGE_DIR"/* "$EXECUTABLE" "$OUTPUT_DIR/Chess-Titans-Remastered.pck" "$ARCHIVE"
printf '%s\n' "$VERSION" > VERSION
python3 - "$VERSION" <<'PY'
import pathlib
import re
import sys

version = sys.argv[1]
if not re.fullmatch(r"\d+\.\d", version):
    print("::error::Version must use the X.Y format, for example 1.3.")
    raise SystemExit(1)
path = pathlib.Path("project.godot")
text = path.read_text(encoding="utf-8")
text, replacements = re.subn(
    r'(?m)^config/version="[^"]*"$',
    'config/version="%s"' % version,
    text,
)
if replacements != 1:
    print("::error::Expected exactly one application/config/version setting in project.godot")
    raise SystemExit(1)
path.write_text(text, encoding="utf-8")
PY

run_checked() {
  local stage="$1"
  shift
  echo "==> $stage"
  if "$@"; then
    echo "<== $stage passed"
  else
    local status=$?
    echo "::error::$stage failed with exit code $status"
    return "$status"
  fi
}

run_checked "Godot version" godot --version

# Import the project and fail early on script/resource errors.
run_checked "Import project and validate scripts" godot --headless --editor --path . --quit

# Rules-only regression suite. No engine or AI is included.
run_checked "Run chess rules regression tests" godot --headless --path . --script res://tests/test_chess_rules.gd

# Start the actual game scene headlessly for a short smoke test. This exercises
# scene construction, procedural models, UI wiring, settings, and audio loading.
run_checked "Run headless scene smoke test" godot --headless --path . --quit-after 3

# The cross-export uses Godot's Windows template, so no Rust or .NET compile is needed.
run_checked "Export Windows desktop executable" godot --headless --path . --export-release "Windows Desktop" "$EXECUTABLE"

if [[ ! -s "$EXECUTABLE" ]]; then
  echo "::error::Godot did not produce the Windows executable."
  exit 1
fi
if [[ ! -s "$OUTPUT_DIR/Chess-Titans-Remastered.pck" ]]; then
  echo "::error::Godot did not produce the Windows resource pack."
  exit 1
fi

cp "$EXECUTABLE" "$OUTPUT_DIR/Chess-Titans-Remastered.pck" "$PACKAGE_DIR/"
cp README.md "$PACKAGE_DIR/README.txt"
cp LICENSE "$PACKAGE_DIR/" 2>/dev/null || true
printf 'Chess Titans Remastered v%s\n\n' "$VERSION" > "$PACKAGE_DIR/VERSION.txt"
cat >> "$PACKAGE_DIR/VERSION.txt" <<'EOF'
Windows x64 desktop build.
Run Chess-Titans-Remastered.exe with the .pck file beside it.
This local two-player build includes chess rules only; no chess engine is bundled.
EOF

(
  cd "$PACKAGE_DIR"
  zip -q -r "../$(basename "$ARCHIVE")" .
)
ls -lh "$EXECUTABLE" "$OUTPUT_DIR/Chess-Titans-Remastered.pck" "$ARCHIVE"
