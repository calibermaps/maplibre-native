#!/usr/bin/env python3
"""Ground height in meters from the public Mapterhorn terrarium tiles (needs Pillow with WebP).

    python3 lib/ground_elevation.py LON LAT [LON LAT ...]

Used to pick the center altitude of a camera and to check that the tour camera stays above ground.
Tiles are cached in $TERRAIN_EXAMPLES_DEM_CACHE (default: a folder in the system temp directory).
"""
import io
import math
import os
import sys
import tempfile
import urllib.request

from PIL import Image

URL = "https://tiles.mapterhorn.com/{z}/{x}/{y}.webp"
CACHE = os.environ.get("TERRAIN_EXAMPLES_DEM_CACHE", os.path.join(tempfile.gettempdir(), "terrain-3d-dem"))
_tiles = {}


def _tile(z, x, y):
    key = (z, x, y)
    if key not in _tiles:
        path = os.path.join(CACHE, f"{z}-{x}-{y}.webp")
        if not os.path.exists(path):
            os.makedirs(CACHE, exist_ok=True)
            req = urllib.request.Request(URL.format(z=z, x=x, y=y), headers={"User-Agent": "maplibre-native-terrain-examples"})
            with urllib.request.urlopen(req, timeout=60) as r, open(path, "wb") as f:
                f.write(r.read())
        _tiles[key] = Image.open(path).convert("RGB")
    return _tiles[key]


def elevation(lon, lat, z=11):
    """Bilinear ground height (m) at lon/lat, decoded from a 512 px terrarium tile."""
    n = 2 ** z
    fx = (lon + 180.0) / 360.0 * n
    fy = (1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n
    tx, ty = int(fx), int(fy)
    img = _tile(z, tx, ty)
    size = img.size[0]
    px, py = (fx - tx) * size - 0.5, (fy - ty) * size - 0.5
    x0, y0 = max(0, min(size - 2, int(math.floor(px)))), max(0, min(size - 2, int(math.floor(py))))
    ax, ay = min(1.0, max(0.0, px - x0)), min(1.0, max(0.0, py - y0))

    def h(ix, iy):
        r, g, b = img.getpixel((ix, iy))
        return r * 256.0 + g + b / 256.0 - 32768.0

    top = h(x0, y0) * (1 - ax) + h(x0 + 1, y0) * ax
    bottom = h(x0, y0 + 1) * (1 - ax) + h(x0 + 1, y0 + 1) * ax
    return top * (1 - ay) + bottom * ay


if __name__ == "__main__":
    args = [float(a) for a in sys.argv[1:]]
    if len(args) < 2 or len(args) % 2:
        sys.exit(__doc__)
    for lon, lat in zip(args[0::2], args[1::2]):
        print(f"{lon} {lat} {elevation(lon, lat):.0f} m")
