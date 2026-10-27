#!/usr/bin/env bash
# Prints one version's section of CHANGELOG.md: everything between its
# "## [x.y.z]" heading and the next version heading. Prints nothing if the
# version has no section.
#
# Usage: scripts/changelog-section.sh <version>
#   e.g. scripts/changelog-section.sh 0.4.16
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <version>" >&2
  exit 2
fi

if [ ! -f CHANGELOG.md ]; then
  echo "$0: CHANGELOG.md not found; run from the repository root" >&2
  exit 1
fi

awk -v ver="$1" '
  $0 ~ "^## \\[" ver "\\]" { grab = 1; next }
  grab && /^## \[/ { exit }
  grab { print }
' CHANGELOG.md
