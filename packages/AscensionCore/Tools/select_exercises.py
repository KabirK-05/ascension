"""Cut the allowlisted rows out of free-exercise-db into the bundled resource.

Usage: select_exercises.py <exercises.json> <allowlist.txt> <out.json>

Only the fields the app shows survive, every row is sorted by id and the JSON is
written with stable key order, so the committed file diffs line by line when the
allowlist changes. Input is untrusted: a row that does not have the shape below is
a hard failure here rather than a surprise on device.
"""

import json
import sys

FIELDS = ("id", "name", "equipment", "primaryMuscles", "secondaryMuscles",
          "instructions", "images")


def main(source_path, allowlist_path, out_path):
    with open(source_path, encoding="utf-8") as handle:
        rows = json.load(handle)
    by_id = {row["id"]: row for row in rows if isinstance(row.get("id"), str)}

    wanted = []
    with open(allowlist_path, encoding="utf-8") as handle:
        for line in handle:
            line = line.split("#", 1)[0].strip()
            if line and line not in wanted:
                wanted.append(line)

    missing = [name for name in wanted if name not in by_id]
    if missing:
        raise SystemExit(f"not in the dataset: {', '.join(missing)}")

    selected = []
    for name in sorted(wanted):
        row = by_id[name]
        kept = {field: row.get(field) for field in FIELDS}
        if not kept["name"] or len(kept["images"]) != 2:
            raise SystemExit(f"{name}: expected a name and two images")
        selected.append(kept)

    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(selected, handle, indent=1, ensure_ascii=False, sort_keys=True)
        handle.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
