#!/usr/bin/env bash
# Build mbgl-render-test-runner with MLN_USE_TRACY, build Tracy's capture and
# csvexport tools from the same Tracy checkout, then record each camera script.
# Run inside ml-build from the tree root:
#   scripts/terrain-evidence/tracy/run_tracy.sh [build dir] [output dir]
set -uo pipefail
B=${1:-build-tracy}
OUT=${2:-/work/p0-tracy}
T=scripts/terrain-evidence/tracy
# Tracy master (Nov 2026) no longer builds with MLN_USE_TRACY: its TracyOpenGL.hpp calls
# glGetIntegerv and friends, which mln only declares in mln::platform. Pin v0.11.1.
TRACY_SRC=${TRACY_SRC:-/work/tracy-v0.11.1}
[ -d "$TRACY_SRC" ] || git clone -q --depth 1 --branch v0.11.1 https://github.com/wolfpld/tracy.git "$TRACY_SRC"
mkdir -p "$OUT"
cmake --preset linux-opengl -B "$B" -DCMAKE_BUILD_TYPE=Release -DMLN_USE_TRACY=ON -DFETCHCONTENT_SOURCE_DIR_TRACY="$TRACY_SRC" -DMLN_WITH_WERROR=OFF \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_C_COMPILER_LAUNCHER=ccache > "$OUT/configure.log" 2>&1 || { tail -5 "$OUT/configure.log"; exit 1; }
cmake --build "$B" --target mbgl-render-test-runner -j6 > "$OUT/build.log" 2>&1 || { grep -m5 'error:' "$OUT/build.log"; exit 1; }
SRC="$TRACY_SRC"
for tool in capture csvexport; do
  if [ ! -x "$B/tracy-$tool/tracy-$tool" ]; then
    cmake -S "$SRC/$tool" -B "$B/tracy-$tool" -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang \
      > "$OUT/$tool-configure.log" 2>&1 || { tail -5 "$OUT/$tool-configure.log"; exit 1; }
    cmake --build "$B/tracy-$tool" -j6 > "$OUT/$tool-build.log" 2>&1 || { grep -m5 'error' "$OUT/$tool-build.log"; exit 1; }
  fi
done
export EGL_PLATFORM=surfaceless LIBGL_ALWAYS_SOFTWARE=1 TRACY_NO_EXIT=1
for name in tilt-60-turn tilt-75-turn pan-and-turn; do
  "$B/tracy-capture/tracy-capture" -o "$OUT/$name.tracy" -f -s 600 > "$OUT/$name-capture.log" 2>&1 &
  CAP=$!
  ( time xvfb-run -a "./$B/mbgl-render-test-runner" --manifestPath="$T/manifest.json" -f "camera/$name" ) > "$OUT/$name-run.log" 2>&1
  wait $CAP
  "$B/tracy-csvexport/tracy-csvexport" "$OUT/$name.tracy" > "$OUT/$name-zones.csv" 2> "$OUT/$name-csvexport.err"
  echo "$name: $(grep -E '^real' "$OUT/$name-run.log") zones=$(($(wc -l < "$OUT/$name-zones.csv") - 1)) trace=$(du -h "$OUT/$name.tracy" | cut -f1)"
done | tee "$OUT/summary.txt"
