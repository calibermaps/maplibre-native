#!/usr/bin/env bash
# ASan + UBSan build (vptr check off: core builds without RTTI, so it only flags googletest) of mbgl-test-runner, then every terrain suite in its own process.
# Run inside the ml-build container from the source tree root:
#   scripts/terrain-evidence/asan.sh [build dir] [output dir]
set -uo pipefail
B=${1:-build-asan}
OUT=${2:-/work/p0-asan}
mkdir -p "$OUT"
CCACHE_DISABLE=1 cmake --preset linux-opengl -B "$B" -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_CXX_FLAGS_DEBUG="-O1 -g1 -fno-omit-frame-pointer -fsanitize=undefined -fno-sanitize=vptr" \
  -DCMAKE_C_FLAGS_DEBUG="-O1 -g1 -fno-omit-frame-pointer -fsanitize=undefined -fno-sanitize=vptr" \
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=undefined" -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=undefined" \
  -DMLN_WITH_SANITIZER=address -DMLN_WITH_WERROR=OFF -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang > "$OUT/configure.log" 2>&1 || { tail -5 "$OUT/configure.log"; exit 1; }
CCACHE_DISABLE=1 cmake --build "$B" --target mbgl-test-runner -j6 > "$OUT/build.log" 2>&1 || { grep -m5 'error:' "$OUT/build.log"; exit 1; }
export ASAN_OPTIONS=detect_leaks=1:abort_on_error=0:symbolize=1
export UBSAN_OPTIONS=print_stacktrace=1
export EGL_PLATFORM=surfaceless LIBGL_ALWAYS_SOFTWARE=1
for s in $(scripts/terrain-evidence/terrain_suites.sh); do
  timeout 900 xvfb-run -a "./$B/mbgl-test-runner" --gtest_filter="$s.*" > "$OUT/$s.log" 2>&1
  rc=$?
  printf '%-28s rc=%-4s asan=%s ubsan=%s leaks=%s %s\n' "$s" "$rc" \
    "$(grep -c 'ERROR: AddressSanitizer' "$OUT/$s.log")" \
    "$(grep -c 'runtime error:' "$OUT/$s.log")" \
    "$(grep -c 'ERROR: LeakSanitizer' "$OUT/$s.log")" \
    "$(grep -oE '\[  (PASSED|FAILED)  \] [0-9]+ tests?' "$OUT/$s.log" | tr '\n' ' ')"
done | tee "$OUT/summary.txt"
