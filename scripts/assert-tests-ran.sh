#!/bin/bash
#
# Reports what a `xcodebuild test` run actually executed, and fails if it executed
# nothing.
#
# `xcodebuild ... test` exits 0 and prints `** TEST SUCCEEDED **` when it runs zero
# tests, and under `-quiet` it prints no count at all — so a green job was never
# evidence that any test had run. Worse, the count xcodebuild does print without
# `-quiet` is XCTest's alone: a suite written entirely in Swift Testing shows
# `Executed 0 tests, with 0 failures` beside a full passing run. This reads the real
# numbers out of the result bundle instead. ASC-26.
#
# Usage: assert-tests-ran.sh <path/to/result.xcresult> [label]
set -euo pipefail

bundle=${1:?usage: assert-tests-ran.sh <result.xcresult> [label]}
label=${2:-tests}

if [ ! -e "$bundle" ]; then
    echo "::error::$label: no result bundle at $bundle — the run produced no results."
    exit 1
fi

xcrun xcresulttool get test-results summary --path "$bundle" --format json \
    | LABEL="$label" python3 -c '
import json
import os
import sys

label = os.environ["LABEL"]
summary = json.load(sys.stdin)

total = summary.get("totalTestCount", 0)
passed = summary.get("passedTests", 0)
failed = summary.get("failedTests", 0)
skipped = summary.get("skippedTests", 0)
result = summary.get("result", "unknown")

print(f"{label}: {total} tests executed — "
      f"{passed} passed, {failed} failed, {skipped} skipped (result: {result})")

for failure in summary.get("testFailures", []):
    name = failure.get("testIdentifierString", "<unknown test>")
    text = failure.get("failureText", "")
    print(f"::error::{label}: {name}: {text}")

if total == 0:
    print(f"::error::{label}: zero tests executed. A test run that executes nothing "
          f"is not a passing test run — the bundle failed to load, every test was "
          f"filtered out, or the target has no tests.")
    sys.exit(1)

if failed or result not in ("Passed", "Expected Failure"):
    sys.exit(1)
'
