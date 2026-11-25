#!/bin/bash
#
# Copies Beardie UI-test screenshots into the repository.
#
# The UI test runner writes screenshots to its temporary directory
# (`$TMPDIR/BeardieUITests/latest`) or, when sandboxed, into its container.
# This script collects them into `.tmp/ui-screenshots/<subfolder>/`, which is
# git-ignored.
#
# Usage:
#   Scripts/collect_ui_screenshots.sh [subfolder]
#
# Example:
#   Scripts/collect_ui_screenshots.sh before
#   Scripts/collect_ui_screenshots.sh after

set -e

SUBDIR="${1:-latest}"

case "$SUBDIR" in
    ""|.|..|*/*|*[!A-Za-z0-9._-]*)
        echo "Invalid subfolder name: $SUBDIR" >&2
        exit 1
        ;;
esac

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER=$(find "$HOME/Library/Containers" -maxdepth 1 -type d -name "*BeardieUITests.xctrunner" 2>/dev/null | head -1)

CANDIDATES=("$REPO/.tmp/ui-screenshots/raw" "$TMPDIR/BeardieUITests/latest")
if [ -n "$CONTAINER" ]; then
    CANDIDATES+=("$CONTAINER/Data/tmp/BeardieUITests/latest")
fi

SRC=""
for candidate in "${CANDIDATES[@]}"; do
    if [ -d "$candidate" ]; then
        SRC="$candidate"
        break
    fi
done

if [ -z "$SRC" ]; then
    echo "Beardie UI-test screenshots were not found." >&2
    echo "Run the BeardieUITests scheme first." >&2
    exit 1
fi

mkdir -p "$REPO/.tmp/ui-screenshots"
rm -rf "$REPO/.tmp/ui-screenshots/$SUBDIR"
cp -R "$SRC" "$REPO/.tmp/ui-screenshots/$SUBDIR"

echo "Screenshots copied to .tmp/ui-screenshots/$SUBDIR"
ls -1 "$REPO/.tmp/ui-screenshots/$SUBDIR"
