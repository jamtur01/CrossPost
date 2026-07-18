#!/usr/bin/env bash
# Builds the GitHub release notes for one tag from CHANGELOG.md and prints
# them to stdout. Single source of truth for the notes template so the
# release and sync-release-notes workflows cannot drift apart again.
#
# Usage: scripts/extract-release-notes.sh <version> <tag>
#   e.g. scripts/extract-release-notes.sh 0.4.16 v0.4.16
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <version> <tag>" >&2
  exit 2
fi

version="$1"
tag="$2"

if [ ! -f CHANGELOG.md ]; then
  echo "$0: CHANGELOG.md not found; run from the repository root" >&2
  exit 1
fi

# Pull this version's section out of CHANGELOG.md (everything between its
# "## [x.y.z]" heading and the next version heading).
section=$(awk -v ver="$version" '
  $0 ~ "^## \\[" ver "\\]" { grab = 1; next }
  grab && /^## \[/ { exit }
  grab { print }
' CHANGELOG.md)

echo "A native macOS app for reading and posting to Mastodon and Bluesky side by side."
if [ -n "$(printf '%s' "$section" | tr -d '[:space:]')" ]; then
  echo
  echo "## What's changed"
  printf '%s\n' "$section"
fi
echo
echo "## Installation"
echo
echo "Download \`CrossPost-${tag}.dmg\`, open it, and drag CrossPost to Applications."
echo "(A zip, \`CrossPost-${tag}.zip\`, is also attached.)"
echo
echo "This build is signed with a Developer ID and notarized by Apple."
