#!/usr/bin/env bash
# Print the gtest suites defined in test/renderer/terrain_*.test.cpp, one per line.
grep -hoE '^TEST(_F|_P)?\(\s*[A-Za-z0-9_]+' test/renderer/terrain_*.test.cpp | sed -E 's/.*\(\s*//' | sort -u
