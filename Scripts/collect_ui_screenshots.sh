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
CONTAINER=$(find "$HOME/Library/Containers" -maxdepth 1 -type d -iname "*beardie*uitests.xctrunner" 2>/dev/null | head -1)

CANDIDATES=("$REPO/.tmp/ui-screenshots/raw")
if [ -n "$CONTAINER" ]; then
    CANDIDATES+=("$CONTAINER/Data/tmp/BeardieUITests/latest")
fi
CANDIDATES+=("$TMPDIR/BeardieUITests/latest")

SRC=""
# Prefer a directory that actually contains the pane capture. A signed
# UI-test runner is sandboxed and writes into its container, while a stale
# temporary directory may contain only failure diagnostics.
for candidate in "${CANDIDATES[@]}"; do
    if [ -f "$candidate/shortcuts-pane.png" ]; then
        SRC="$candidate"
        break
    fi
done

if [ -z "$SRC" ]; then
    for candidate in "${CANDIDATES[@]}"; do
        if [ -d "$candidate" ]; then
            SRC="$candidate"
            break
        fi
    done
fi

if [ -z "$SRC" ]; then
    echo "Beardie UI-test screenshots were not found." >&2
    echo "Run the BeardieUITests scheme first." >&2
    exit 1
fi

DEST="$REPO/.tmp/ui-screenshots/$SUBDIR"
mkdir -p "$REPO/.tmp/ui-screenshots"
rm -rf "$DEST"
mkdir -p "$DEST"

# Failure diagnostics are useful for debugging, but stale failure PNGs from
# earlier runs must not replace the current capture screenshot.
find "$SRC" -maxdepth 1 -type f -name "*.png" ! -name "failure-*" -exec cp {} "$DEST/" \;
if [ -z "$(ls -A "$DEST")" ]; then
    cp -R "$SRC/." "$DEST/"
fi

echo "Screenshots copied to .tmp/ui-screenshots/$SUBDIR"
ls -1 "$DEST"
