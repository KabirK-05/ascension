#!/usr/bin/env bash
# Rebuilds the bundled exercise-library resource from free-exercise-db.
#
#   packages/AscensionCore/Tools/build-exercise-library.sh
#
# Source: https://github.com/yuhonas/free-exercise-db (Unlicense, public domain).
# Needs curl, python3 and ImageMagick 7 (`brew install imagemagick`).
#
# Everything it writes is derived from the allowlist beside it, so the resource is
# reproducible and a reviewer can diff the output rather than trust it.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package="$(dirname "$here")"
out="$package/Sources/AscensionCore/Resources/ExerciseLibrary"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

raw="https://raw.githubusercontent.com/yuhonas/free-exercise-db/main"

# Downloaded data is untrusted: it lands in its own directory and is only ever
# read as an argument, never executed and never on an interpreter's path.
mkdir -p "$work/untrusted"
curl -fsS -o "$work/untrusted/exercises.json" "$raw/dist/exercises.json"

rm -rf "$out"
mkdir -p "$out/Images"

python3 -I "$here/select_exercises.py" \
  "$work/untrusted/exercises.json" \
  "$here/exercise-library-allowlist.txt" \
  "$out/exercises.json"

# Images are resized to the width the detail view actually draws them at — two
# side by side on an iPhone, ~160 pt each, so 480 px covers 3x without waste.
while read -r id; do
  mkdir -p "$out/Images/$id"
  for n in 0 1; do
    curl -fsS -o "$work/untrusted/src.jpg" "$raw/exercises/$id/$n.jpg"
    magick "$work/untrusted/src.jpg" -resize 480x -strip \
      -interlace Plane -quality 72 "$out/Images/$id/$n.jpg"
  done
done < <(python3 -I -c '
import json, sys
for row in json.load(open(sys.argv[1])):
    print(row["id"])
' "$out/exercises.json")

echo "wrote $(python3 -I -c '
import json, sys
print(len(json.load(open(sys.argv[1]))))
' "$out/exercises.json") exercises, $(du -sh "$out" | cut -f1) on disk"
