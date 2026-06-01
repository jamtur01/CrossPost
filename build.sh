#!/usr/bin/env bash
#
# Build Crosspost.app into ./build/ for local testing.
#
# Usage:
#   ./build.sh           Build the app bundle.
#   ./build.sh --run      Build, then launch it.
#   ./build.sh --release  Build the Release configuration instead of Debug.
#
set -euo pipefail
cd "$(dirname "$0")"

configuration="Debug"
run=false
for arg in "$@"; do
  case "$arg" in
  --run | -r) run=true ;;
  --release) configuration="Release" ;;
  *)
    echo "error: unknown argument '$arg'" >&2
    exit 2
    ;;
  esac
done

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi

derived_data="$PWD/build/DerivedData"
dest="$PWD/build/Crosspost.app"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building Crosspost ($configuration)"
xcodebuild build \
  -project Crosspost.xcodeproj \
  -scheme Crosspost \
  -configuration "$configuration" \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  -quiet

src="$derived_data/Build/Products/$configuration/Crosspost.app"
if [ ! -d "$src" ]; then
  echo "error: build did not produce $src" >&2
  exit 1
fi

rm -rf "$dest"
cp -R "$src" "$dest"
echo "==> Built: $dest"

if [ "$run" = true ]; then
  echo "==> Launching"
  open "$dest"
fi
