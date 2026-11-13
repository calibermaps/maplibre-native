#!/usr/bin/env python3
"""Shrink a PNG to a 256-color palette so previews stay small. Does nothing if Pillow is missing.

    python3 lib/shrink_png.py FILE.png
"""
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit(0)

path = sys.argv[1]
img = Image.open(path).convert("RGB")
img.quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(path, optimize=True)
