#!/usr/bin/env bash
set -e

# Resolve repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Check for .env.json
if [ ! -f ".env.json" ]; then
  echo "Error: .env.json not found in repository root. Copy .env.json.example to .env.json and fill in your keys." >&2
  exit 1
fi

# Ensure dist directory exists
mkdir -p dist

echo "Building release APK..."
flutter build apk --release --dart-define-from-file=.env.json

# Copy artifact to dist
OUTPUT_APK="build/app/outputs/flutter-apk/app-release.apk"
TARGET_APK="dist/prism-v3.0.0-midterm.apk"

if [ -f "$OUTPUT_APK" ]; then
  cp "$OUTPUT_APK" "$TARGET_APK"
  echo "Build complete: $TARGET_APK"
  
  # Compute and print SHA-256
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$TARGET_APK"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$TARGET_APK"
  fi
else
  echo "Error: Output APK not found at $OUTPUT_APK" >&2
  exit 1
fi
