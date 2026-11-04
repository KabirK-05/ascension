#!/bin/bash
#
# Prints the UDID of a simulator CI can test on, as `UDID<tab>NAME<tab>OS`.
#
# A hardcoded destination (`name=iPhone 17 Pro`) breaks the moment a runner image
# stops shipping that model, which this project has already hit once. Resolving the
# device at run time means the workflow follows whatever the image provides.
#
# Picks the newest installed iOS runtime, then the first available iPhone on it —
# newest, because the app's deployment target is the newest iOS and an older runtime
# is not a valid destination for it.
set -euo pipefail

IFS=$'\t' read -r udid name os <<<"$(
    xcrun simctl list devices available --json | python3 -c '
import json
import re
import sys

runtimes = json.load(sys.stdin)["devices"]


def version(identifier):
    match = re.search(r"SimRuntime\.iOS-([0-9]+)(?:-([0-9]+))?$", identifier)
    return (int(match.group(1)), int(match.group(2) or 0)) if match else None


candidates = [(v, i, d) for i, d in runtimes.items() if (v := version(i)) and d]
if not candidates:
    sys.exit("no iOS simulator runtime with an available device is installed")

_, identifier, devices = max(candidates, key=lambda c: c[0])
iphones = [d for d in devices if d["name"].startswith("iPhone")]
device = (iphones or devices)[0]
major, minor = version(identifier)
print(device["udid"], device["name"], f"{major}.{minor}", sep="\t")
'
)"

printf '%s\t%s\t%s\n' "$udid" "$name" "$os"
