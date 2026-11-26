#!/usr/bin/env python3
"""Pixel-diff two UI screenshots.

Usage:
    Scripts/diff_ui_screenshots.py before.png after.png

Exit codes:
    0 — images are identical
    1 — images differ
    2 — usage error or image size mismatch

Requires Pillow (the project environment already has it).
"""

import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops
except ImportError:
    print("Pillow is required: python3 -m pip install Pillow", file=sys.stderr)
    sys.exit(2)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {Path(sys.argv[0]).name} BEFORE.png AFTER.png", file=sys.stderr)
        return 2

    before_path = Path(sys.argv[1])
    after_path = Path(sys.argv[2])

    try:
        # Compare RGB, not RGBA: AppKit screenshots can have an all-zero alpha
        # channel, and ImageChops.getbbox() would then report "identical" even
        # when the visible pixels differ.
        before = Image.open(before_path).convert("RGB")
        after = Image.open(after_path).convert("RGB")
    except OSError as error:
        print(f"Could not open screenshots: {error}", file=sys.stderr)
        return 2

    if before.size != after.size:
        print(f"Image sizes differ: {before.size} vs {after.size}", file=sys.stderr)
        return 2

    diff = ImageChops.difference(before, after)
    bbox = diff.getbbox()

    if bbox is None:
        print("Screenshots are identical")
        return 0

    try:
        pixels = diff.get_flattened_data()
    except AttributeError:
        pixels = diff.getdata()

    changed = sum(1 for pixel in pixels if any(pixel))
    print(f"Screenshots differ: {changed} pixels, bbox={bbox}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
