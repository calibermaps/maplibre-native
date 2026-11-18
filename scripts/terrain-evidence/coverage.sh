#!/usr/bin/env bash
# Source-based llvm-cov build of mbgl-test-runner, run every terrain suite, report
# line coverage for the scope files. Run inside ml-build from the source tree root:
#   scripts/terrain-evidence/coverage.sh [build dir] [output dir]
set -uo pipefail
B=${1:-build-cov}
OUT=${2:-/work/p0-cov}
mkdir -p "$OUT/profraw"
FLAGS="-O0 -g0 -fprofile-instr-generate -fcoverage-mapping"
CCACHE_DISABLE=1 cmake --preset linux-opengl -B "$B" -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_CXX_FLAGS_DEBUG="$FLAGS" -DCMAKE_C_FLAGS_DEBUG="$FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="-fprofile-instr-generate" -DMLN_WITH_WERROR=OFF \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang \
  > "$OUT/configure.log" 2>&1 || { tail -5 "$OUT/configure.log"; exit 1; }
CCACHE_DISABLE=1 cmake --build "$B" --target mbgl-test-runner -j6 > "$OUT/build.log" 2>&1 || { grep -m5 'error:' "$OUT/build.log"; exit 1; }
export EGL_PLATFORM=surfaceless LIBGL_ALWAYS_SOFTWARE=1
for s in $(scripts/terrain-evidence/terrain_suites.sh); do
  LLVM_PROFILE_FILE="$OUT/profraw/$s-%p.profraw" timeout 900 xvfb-run -a "./$B/mbgl-test-runner" --gtest_filter="$s.*" > "$OUT/$s.log" 2>&1
  echo "$s rc=$? $(grep -oE '\[  (PASSED|FAILED)  \] [0-9]+ tests?' "$OUT/$s.log" | tr '\n' ' ')"
done | tee "$OUT/runs.txt"
llvm-profdata merge -sparse "$OUT"/profraw/*.profraw -o "$OUT/terrain.profdata"
SCOPE=$(grep -E '\.(cpp|hpp)$' .claude/scope.txt | grep -v '^include/mln/shaders/' | sed "s#^#$(pwd)/#" | while read f; do [ -f "$f" ] && echo "$f"; done)
llvm-cov report "./$B/mbgl-test-runner" -instr-profile="$OUT/terrain.profdata" $SCOPE > "$OUT/report.txt" 2>"$OUT/report.err"
llvm-cov export "./$B/mbgl-test-runner" -instr-profile="$OUT/terrain.profdata" -format=lcov $SCOPE > "$OUT/terrain.lcov" 2>>"$OUT/report.err"
tail -1 "$OUT/report.txt"
