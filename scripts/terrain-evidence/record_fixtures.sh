#!/usr/bin/env bash
# Add the fixtures that new render tests need to metrics/cache-style.db without
# changing any entry already in it. Run inside ml-build from the tree root:
#   scripts/terrain-evidence/record_fixtures.sh <runner> <filter regex>
# Records into a scratch copy with --online against fixture_server.py, then
# copies only the missing rows into the real database (INSERT OR IGNORE).
set -uo pipefail
RUNNER=$1
FILTER=$2
HOSTS="tiles glyphs image sprites geojson data"
cp /etc/hosts /tmp/hosts.orig
for h in $HOSTS; do echo "127.0.0.1 $h" >> /etc/hosts; done
python3 scripts/terrain-evidence/fixture_server.py metrics/integration 2> /tmp/fixture-server.log &
SERVER=$!
sleep 1
mkdir -p /tmp/record
cp metrics/cache-style.db /tmp/record/cache-style.db
sed -e 's#"cache_path": *"[^"]*"#"cache_path": "/tmp/record/cache-style.db"#' metrics/linux-opengl.json > metrics/record-manifest.json
xvfb-run -a "$RUNNER" --manifestPath=metrics/record-manifest.json --online -f "$FILTER" > /tmp/record/run.log 2>&1
kill $SERVER
cp /tmp/hosts.orig /etc/hosts
rm -f metrics/record-manifest.json metrics/record-manifest.html
python3 - <<'PY'
import sqlite3
db = sqlite3.connect("metrics/cache-style.db")
db.execute("ATTACH '/tmp/record/cache-style.db' AS rec")
before = [db.execute(f"select count(*) from {t}").fetchone()[0] for t in ("resources", "tiles")]
db.execute("""INSERT OR IGNORE INTO resources (url, kind, expires, modified, etag, data, compressed, accessed, must_revalidate)
              SELECT url, kind, NULL, modified, etag, data, compressed, accessed, 0 FROM rec.resources""")
db.execute("""INSERT OR IGNORE INTO tiles (url_template, pixel_ratio, z, x, y, expires, modified, etag, data, compressed, accessed, must_revalidate)
              SELECT url_template, pixel_ratio, z, x, y, NULL, modified, etag, data, compressed, accessed, 0 FROM rec.tiles""")
db.commit()
after = [db.execute(f"select count(*) from {t}").fetchone()[0] for t in ("resources", "tiles")]
print(f"resources +{after[0]-before[0]}, tiles +{after[1]-before[1]}")
db.execute("DETACH rec")
db.execute("VACUUM")
PY
echo "fixture server: $(grep -c '^HIT' /tmp/fixture-server.log) served, $(grep -c '^MISS' /tmp/fixture-server.log) missing"
grep '^MISS' /tmp/fixture-server.log | sort -u | head -20
