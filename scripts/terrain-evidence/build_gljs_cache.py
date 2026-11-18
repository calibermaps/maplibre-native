#!/usr/bin/env python3
"""Build metrics/cache-terrain-gljs.db = metrics/cache-style.db plus the rows in
metrics/cache-terrain-gljs-additions.db (fixtures the GL JS terrain ports need).

The ported tests run from metrics/linux-opengl-terrain-gljs.json, which reads that
combined database. metrics/cache-style.db stays unchanged: adding these fixtures to
it changes the pictures of terrain/heatmap and terrain/fill-extrusion-occluded.
Run from the repo root.
"""
import shutil
import sqlite3

shutil.copyfile("metrics/cache-style.db", "metrics/cache-terrain-gljs.db")
db = sqlite3.connect("metrics/cache-terrain-gljs.db")
db.execute("ATTACH 'metrics/cache-terrain-gljs-additions.db' AS add_")
db.execute("INSERT OR IGNORE INTO resources (url, kind, expires, modified, etag, data, compressed, accessed, must_revalidate) "
           "SELECT url, kind, expires, modified, etag, data, compressed, accessed, must_revalidate FROM add_.resources")
db.execute("INSERT OR IGNORE INTO tiles (url_template, pixel_ratio, z, x, y, expires, modified, etag, data, compressed, accessed, must_revalidate) "
           "SELECT url_template, pixel_ratio, z, x, y, expires, modified, etag, data, compressed, accessed, must_revalidate FROM add_.tiles")
db.commit()
print("resources", db.execute("select count(*) from resources").fetchone()[0],
      "tiles", db.execute("select count(*) from tiles").fetchone()[0])
