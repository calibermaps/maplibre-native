#!/usr/bin/env python3
"""PreToolUse hook: keep agents out of vendored code, generated GL shader
headers and build folders, and keep build or test logs filtered.

Exit code 2 blocks the tool call and shows the message to the model.
"""
import json
import re
import sys

BLOCKED_PATHS = [
    (re.compile(r"(^|/)vendor/"), "vendor/ is third-party code; it is out of scope"),
    (re.compile(r"(^|/)include/mln/shaders/gl/"),
     "include/mln/shaders/gl/ is generated from shaders/*.glsl; read the .glsl file instead"),
    (re.compile(r"(^|/)build[^/]*/"), "build folders hold generated output; read the tool's report instead"),
    (re.compile(r"(^|/)platform/windows/vendor/"), "vendored code is out of scope"),
]

# Commands that produce long logs and must be piped through grep or tail.
LOUD_COMMANDS = re.compile(
    r"(cmake\s+--build|ninja\b|make\b|mbgl-test-runner|mbgl-render-test-runner|bazel\s+(build|test))"
)
FILTERS = re.compile(r"\|\s*(grep|tail|head|rg|wc)\b|>\s*\S+")


def deny(message):
    print(message, file=sys.stderr)
    sys.exit(2)


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    tool = event.get("tool_name", "")
    args = event.get("tool_input", {}) or {}

    if tool in ("Read", "Edit", "Write", "NotebookEdit"):
        path = args.get("file_path", "") or args.get("notebook_path", "")
        for pattern, why in BLOCKED_PATHS:
            if pattern.search(path):
                deny(f"Blocked read of {path}: {why}.")
    elif tool.startswith("mcp__serena__"):
        path = args.get("relative_path", "") or ""
        for pattern, why in BLOCKED_PATHS:
            if path and pattern.search(path.rstrip("/") + "/"):
                deny(f"Blocked Serena lookup in {path}: {why}.")
    elif tool in ("Grep", "Glob"):
        path = args.get("path", "") or ""
        for pattern, why in BLOCKED_PATHS:
            if pattern.search(path.rstrip("/") + "/"):
                deny(f"Blocked search in {path}: {why}.")
    elif tool == "Bash":
        command = args.get("command", "")
        for pattern, why in BLOCKED_PATHS:
            if re.search(r"\b(cat|less|more|head|tail|sed|awk)\b[^|;&]*" + pattern.pattern.replace("(^|/)", "(\\s|/)"),
                         command):
                deny(f"Blocked: {why}.")
        if LOUD_COMMANDS.search(command) and not FILTERS.search(command):
            deny("Pipe build and test output through grep or tail (or redirect it to a file).")


if __name__ == "__main__":
    main()
