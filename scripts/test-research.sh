#!/bin/sh
# test-research.sh
# Created 2026-11-27 · Claude Code
# Runs research-study schedule checks without Swift Package Manager or XCTest.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/still-research-tests.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

swiftc \
    "$PROJECT_ROOT/Sources/StillCore/StillCore.swift" \
    "$PROJECT_ROOT/Sources/StillCore/DailyEvent.swift" \
    "$PROJECT_ROOT/Sources/StillCore/StillNote.swift" \
    "$PROJECT_ROOT/Sources/StillCore/ResearchStudy.swift" \
    "$SCRIPT_DIR/test-research.swift" \
    -o "$TEMP_DIR/test-research"

"$TEMP_DIR/test-research"
