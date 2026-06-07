#!/usr/bin/env bash
#
# Build CrossPost.app into ./build/ for local testing.
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
dest="$PWD/build/CrossPost.app"

echo "==> Generating Xcode project"
xcodegen generate

# Release defaults to a universal build; restrict to the host arch (arm64 on
# Apple Silicon) so release builds compile in roughly half the time.
arch_args=()
if [ "$configuration" = "Release" ]; then
  arch_args=(ONLY_ACTIVE_ARCH=YES)
fi

# Let CI stamp the release version from the git tag so the bundle's
# CFBundleShortVersionString matches what's shipped (see the release workflow).
version_args=()
if [ -n "${CROSSPOST_MARKETING_VERSION:-}" ]; then
  version_args=(MARKETING_VERSION="$CROSSPOST_MARKETING_VERSION")
fi

# Show full build output in CI (so progress is visible); stay quiet locally.
quiet_args=(-quiet)
if [ -n "${CI:-}" ]; then
  quiet_args=()
fi

echo "==> Building CrossPost ($configuration)"
# Use the ${arr[@]+"${arr[@]}"} form so expanding an empty array doesn't trip
# `set -u` on macOS's bash 3.2 (used by GitHub runners).
xcodebuild build \
  -project CrossPost.xcodeproj \
  -scheme CrossPost \
  -configuration "$configuration" \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  ${arch_args[@]+"${arch_args[@]}"} \
  ${version_args[@]+"${version_args[@]}"} \
  ${quiet_args[@]+"${quiet_args[@]}"}

src="$derived_data/Build/Products/$configuration/CrossPost.app"
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
