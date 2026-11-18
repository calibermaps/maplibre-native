#!/usr/bin/env bash
# Terrain render tests under ASan + UBSan. Reuses the build dir that asan.sh configured.
# Run inside ml-build from the tree root, after build_gljs_cache.py:
#   scripts/terrain-evidence/asan_render.sh [build dir] [output dir]
set -uo pipefail
B=${1:-build-asan}
OUT=${2:-/work/p0-asan}
mkdir -p "$OUT"
CCACHE_DISABLE=1 cmake --build "$B" --target mbgl-render-test-runner -j6 > "$OUT/build-render.log" 2>&1 || { grep -m5 'error:' "$OUT/build-render.log"; exit 1; }
export ASAN_OPTIONS=detect_leaks=1:symbolize=1 UBSAN_OPTIONS=print_stacktrace=1
for t in $(ls metrics/integration/render-tests/terrain); do
  [ -f "metrics/integration/render-tests/terrain/$t/style.json" ] || t="$t/$(ls metrics/integration/render-tests/terrain/$t | head -1)"
  timeout 900 xvfb-run -a "./$B/mbgl-render-test-runner" --manifestPath=metrics/linux-opengl-terrain-gljs.json -f "terrain/$t/" \
    > "$OUT/render-${t//\//__}.log" 2>&1
  rc=$?
  printf '%-45s rc=%-4s asan=%s ubsan=%s leaks=%s\n' "$t" "$rc" \
    "$(grep -c 'ERROR: AddressSanitizer' "$OUT/render-${t//\//__}.log")" \
    "$(grep -c 'runtime error:' "$OUT/render-${t//\//__}.log")" \
    "$(grep -c 'ERROR: LeakSanitizer' "$OUT/render-${t//\//__}.log")"
done | tee "$OUT/render-summary.txt"
