#!/usr/bin/env bash
#
# Lint the Swift sources. CI runs this; so does the pre-commit hook.
#
# Usage:
#   ./lint.sh         Check formatting (SwiftFormat) and lint (SwiftLint --strict).
#   ./lint.sh --fix   Apply SwiftFormat and SwiftLint autocorrections first.
#
set -euo pipefail
cd "$(dirname "$0")"

fix=false
for arg in "$@"; do
  case "$arg" in
  --fix) fix=true ;;
  *)
    echo "error: unknown argument '$arg'" >&2
    exit 2
    ;;
  esac
done

for tool in swiftformat swiftlint; do
  if ! command -v "$tool" >/dev/null; then
    echo "error: $tool not found. Install it with: brew install $tool" >&2
    exit 1
  fi
done

if $fix; then
  swiftformat --quiet .
  swiftlint lint --fix --quiet
fi

swiftformat --lint --quiet .
swiftlint lint --strict --quiet
