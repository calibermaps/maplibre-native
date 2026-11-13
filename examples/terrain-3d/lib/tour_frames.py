#!/usr/bin/env python3
"""Turn the camera stops in tour.txt into one camera per frame, and check the camera stays above ground.

    python3 lib/tour_frames.py STYLE.json TOUR.txt FRAMES_PER_SEGMENT [MIN_CLEARANCE_M] [WIDTH HEIGHT]

Prints one line per frame on stdout:  index lon lat zoom pitch bearing centerAltitude
Prints a clearance report on stderr and exits 1 if the camera would come closer to the ground
than MIN_CLEARANCE_M (default 120 m). Camera position uses the default 36.87 degree field of view.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ground_elevation import elevation  # noqa: E402

EARTH = 40075016.686
FOV = math.radians(36.87)


def ease(t):
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_angle(a, b, t):
    return a + ((b - a + 180) % 360 - 180) * t


def main():
    style_path, tour_path, per_seg = sys.argv[1], sys.argv[2], int(sys.argv[3])
    min_clear = float(sys.argv[4]) if len(sys.argv) > 4 else 120.0
    width, height = (float(sys.argv[5]), float(sys.argv[6])) if len(sys.argv) > 6 else (640.0, 400.0)
    exag = json.load(open(style_path))["terrain"]["exaggeration"]
    stops = [[float(v) for v in line.split()[:5]] for line in open(tour_path) if line.strip() and not line.startswith("#")]
    frames = []
    for a, b in zip(stops, stops[1:]):
        for i in range(per_seg):
            t = ease(i / per_seg)
            frames.append([lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t), lerp_angle(a[4], b[4], t)])
    frames.append(stops[-1])

    worst = (1e9, -1)
    for idx, (lon, lat, zoom, pitch, bearing) in enumerate(frames):
        ground = elevation(lon, lat) * exag
        mpp = EARTH * math.cos(math.radians(lat)) / (512.0 * 2 ** zoom)  # meters per pixel at the center
        dist = 0.5 * height / math.tan(FOV / 2) * mpp                      # camera to center, meters
        p, b = math.radians(pitch), math.radians(bearing)
        back = dist * math.sin(p)                                          # horizontal offset, opposite to the view direction
        cam_lat = lat - math.degrees(back * math.cos(b) / 6371008.8)
        cam_lon = lon - math.degrees(back * math.sin(b) / (6371008.8 * math.cos(math.radians(lat))))
        cam_alt = ground + dist * math.cos(p)
        clearance = cam_alt - elevation(cam_lon, cam_lat) * exag
        worst = min(worst, (clearance, idx))
        print(f"{idx} {lon:.5f} {lat:.5f} {zoom:.3f} {pitch:.2f} {bearing % 360:.2f} {ground:.0f}")
        print(f"frame {idx:3d}: center ground {ground:6.0f} m, camera clearance {clearance:6.0f} m", file=sys.stderr)
    print(f"lowest camera clearance above ground: {worst[0]:.0f} m (frame {worst[1]}), limit {min_clear:.0f} m", file=sys.stderr)
    sys.exit(1 if worst[0] < min_clear else 0)


if __name__ == "__main__":
    main()
