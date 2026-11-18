# Terrain 3D work in calibermaps/maplibre-native

This file is for agents working on 3D terrain (upstream PR 4190). It sits on the
work branch `terrain-3d-phase0-evidence`, never on `main` or `feature/terrain-3d`.

## Scope

- Review and change only the files listed in `.claude/scope.txt` (the core diff of
  `feature/terrain-3d` against `main`: `src`, `include`, `shaders`; 321 files).
- `TERRAIN.md` describes the architecture. Read the section for your slice, not the whole file.
- Use the code index before reading files: the Serena MCP tools (symbol outline, one
  function's body, references) or `ast-grep`/`ctags`. Read a function, not a 1,500-line file.

## Do not read

- `vendor/` (third-party code).
- `include/mln/shaders/gl/` (generated from `shaders/*.glsl`; read the `.glsl` file).
  The `mtl/`, `vulkan/` and `webgpu/` folders next to it are hand-written shader source and are in scope.
- Any `build*/` folder. Read the tool's report instead.
- Full build or test logs. Pipe through `grep` or `tail`, or redirect to a file.

The hook in `.claude/hooks/block_reads.py` enforces these.

## Evidence first

Every finding needs file:line plus evidence: a failing test, a sanitizer trace, a failed picture
test, a coverage gap or a measurement. Run the tool, then judge its output.

## Build and test (Linux container `ml-build`, on the Intel Mac)

The container has no `.git`. Copy a branch in with
`git archive HEAD | docker exec -i ml-build tar -xf - -C /work/src-phase0`.
Vendor folders there are hard links into `/work/src-4915sa` (same submodule commits).
The container disk is nearly full: delete object files after a sanitizer or coverage run.

Configure and build (Release, used for picture tests and the compile database):

    cmake --preset linux-opengl -B build-rt -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
      -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_C_COMPILER_LAUNCHER=ccache -DMLN_WITH_WERROR=OFF
    cmake --build build-rt --target mbgl-render-test-runner mbgl-test-runner -j7 2>&1 | tail -3

Unit tests, one suite per process:

    EGL_PLATFORM=surfaceless LIBGL_ALWAYS_SOFTWARE=1 timeout 300 xvfb-run -a \
      ./build-rt/mbgl-test-runner --gtest_filter='TerrainCamera.*' 2>&1 | tail -5

Terrain picture tests (40 cases, 32 ported from GL JS). The ports need fixtures that
`metrics/cache-style.db` lacks, so they run from their own manifest and database
(adding the fixtures to the shared database changes two native baselines):

    python3 scripts/terrain-evidence/build_gljs_cache.py
    xvfb-run -a ./build-rt/mbgl-render-test-runner \
      --manifestPath=metrics/linux-opengl-terrain-gljs.json -f 'terrain/' 2>&1 | tail -5
    python3 scripts/terrain-evidence/parity_report.py metrics/linux-opengl-terrain-gljs.html <out dir> <ported ids file>

The ports are on the normal manifests' ignore list. New fixtures go in with
`scripts/terrain-evidence/record_fixtures.sh`.
Results and the gap list: `upstream-previews/terrain-3d-parity-tests.md` on the host.

## Code index

- `.mcp.json` starts Serena 1.7.0 (clangd 19 underneath), read-only, with only its lookup
  tools on: `get_symbols_overview` (use `depth: 1` for a class outline), `find_symbol`
  (`name_path_pattern` like `RenderTerrain/updateElevationIndex`, `include_body: true` returns
  just that function), `find_referencing_symbols`, `find_implementations`, `find_declaration`,
  `get_diagnostics_for_file`. Always pass `relative_path` to narrow the search.
  `.serena/project.yml` limits it to `src`, `include` (not `include/mln/shaders/gl`) and
  `test/renderer`. Paths in `.mcp.json` are for the Intel Mac.
- Make the compile database first: `scripts/terrain-evidence/export_compile_db.sh` copies the
  container's Linux database, generated headers and vendor headers, and rewrites paths to this
  checkout. Then `serena project index .` once (about an hour on the Intel Mac).
  Metal, Vulkan and WebGPU files are not in the database; use `ast-grep` for those.
- `ast-grep` (`sg`), `lizard` and `jscpd` are installed on the Mac. Universal Ctags is in the
  container only: `docker exec ml-build ctags ...`.

Sanitizer and coverage runs of the 20 terrain suites (about an hour each; the container
needs `libclang-rt-18-dev`): `scripts/terrain-evidence/asan.sh` and `coverage.sh`.
Tracy camera scripts (tilt 60, tilt 75, pan and turn): `scripts/terrain-evidence/tracy/run_tracy.sh`
(pins Tracy v0.11.1; master no longer builds with `MLN_USE_TRACY`; needs `libdbus-1-dev`).
Phase 0 output: `upstream-previews/terrain-3d-phase0-evidence/` on the host.

## Rules

- Branch off `feature/terrain-3d`. Never push to the fork's `main` or `feature/terrain-3d`.
- Before pushing a fork branch, check it is not the head of an open upstream PR.
- Draft PRs only, inside calibermaps/maplibre-native. No upstream PRs, comments or issues.
- No hosted GitHub Actions runners. Tests run in Docker on the Intel Mac or on the M1.
- Subagents: Sonnet 5.5 for judgement, Haiku 5.5 for mechanical work; at most two at a time.
- American English, short plain reports, no attribution lines.
