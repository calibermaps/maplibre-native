#!/usr/bin/env python3
"""Write the three Tracy camera scripts as render tests with camera operations.

Each script renders one frame per step ("wait"), over the Innsbruck terrain
fixtures in metrics/cache-style.db: tilt 60 turn, tilt 75 turn, and a pan with a turn.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
CENTER = [11.52517, 47.34487]
BASE = {
    "version": 8,
    "zoom": 12,
    "bearing": 0,
    "center": CENTER,
    "sources": {
        "terrain": {"type": "raster-dem", "tiles": ["local://tiles/terrain-shading/{z}-{x}-{y}.terrain.png"],
                    "maxzoom": 12, "tileSize": 256},
        "osm": {"type": "raster", "tiles": ["local://tiles/number/{z}.png"], "maxzoom": 17, "tileSize": 256},
    },
    "terrain": {"source": "terrain", "exaggeration": 1.5},
    "layers": [
        {"id": "background", "type": "background", "paint": {"background-color": "#ccddee"}},
        {"id": "osm", "type": "raster", "source": "osm"},
        {"id": "hillshade", "type": "hillshade", "source": "terrain"},
    ],
}


def turn(pitch):
    ops = [["setPitch", pitch], ["wait"]]
    for bearing in range(10, 361, 10):
        ops += [["setBearing", bearing], ["wait"]]
    return ops


def pan_and_turn():
    ops = [["setPitch", 60], ["wait"]]
    for i in range(1, 37):
        ops += [["setCenter", [CENTER[0] + 0.004 * i, CENTER[1] + 0.002 * i]], ["setBearing", 5 * i], ["wait"]]
    return ops


SCRIPTS = {"tilt-60-turn": (60, turn(60)), "tilt-75-turn": (75, turn(75)), "pan-and-turn": (60, pan_and_turn())}

def variants():
    for name, (pitch, ops) in SCRIPTS.items():
        yield name, pitch, ops, True
        yield name + "-no-terrain", pitch, ops, False  # control: same path, no terrain


for name, pitch, ops, with_terrain in variants():
    style = json.loads(json.dumps(BASE))
    if not with_terrain:
        style.pop("terrain")
    style["pitch"] = pitch
    style["metadata"] = {"test": {"width": 512, "height": 512, "maxPitch": 85, "operations": ops,
                                  "description": f"Tracy camera script {name}: one frame per step"}}
    folder = os.path.join(HERE, "render-tests", "camera", name)
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "style.json"), "w") as f:
        json.dump(style, f, indent=2)
        f.write("\n")
    print(folder, len(ops), "operations")
