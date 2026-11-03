"""Compare the field names ExportKit writes against `edge/src/contract.ts`.

`docs/EXPORT_SCHEMA.md` is the prose contract; `edge/src/contract.ts` is the only
place those names live on the edge, and `export.json` is where they leave the device.
A rename on either side is a silent break, so this reads both and diffs them.

    python3 packages/ExportKit/Scripts/verify-contract-field-names.py .

Run it from the repo root, after the goldens are current. Exits non-zero on a
divergence and names the offending fields. Not in CI: `edge/` is a different job and
this is a cross-language check a reviewer runs once per contract change.
"""
import json, re, sys, pathlib

root = pathlib.Path(sys.argv[1])
ts = (root / "edge/src/contract.ts").read_text()
export = json.loads((root / "packages/ExportKit/Tests/ExportKitTests/Golden/export.expected.json").read_text())

def zod_keys(name):
    """Top-level keys of `export const <name> = z.strictObject({...})`."""
    start = ts.index(f"export const {name} = z.strictObject({{")
    depth, i = 0, ts.index("{", start)
    while True:
        if ts[i] == "{": depth += 1
        elif ts[i] == "}":
            depth -= 1
            if depth == 0: break
        i += 1
    body = ts[ts.index("{", start) + 1 : i]
    # Strip nested braces and block comments so only this level's keys remain.
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    flat, depth = [], 0
    for ch in body:
        if ch in "{([": depth += 1
        elif ch in "})]": depth -= 1
        elif depth == 0: flat.append(ch)
    return [m.group(1) for m in re.finditer(r"^\s*(\w+):", "".join(flat), re.M)]

def string_array(name):
    """Members of `export const <name> = ["a", "b"] as const`."""
    block = re.search(rf"export const {name} = \[(.*?)\] as const", ts, re.S).group(1)
    return re.findall(r'"(\w+)"', block)

checks = {
    "DayRollup": (zod_keys("DayRollup"), export["rollups"][0]),
    "nutrition": (zod_keys("Nutrition"), export["rollups"][0]["nutrition"]),
    "activity": (zod_keys("Activity"), export["rollups"][0]["activity"]),
    "sleep": (zod_keys("Sleep"), export["rollups"][0]["sleep"]),
    "vitals": (zod_keys("Vitals"), export["rollups"][0]["vitals"]),
    "body": (zod_keys("Body"), export["rollups"][0]["body"]),
    "training": (zod_keys("Training"), export["rollups"][0]["training"]),
    "wins": (zod_keys("Wins"), export["rollups"][0]["wins"]),
    "checkIn": (zod_keys("CheckIn"), export["rollups"][0]["checkIn"]),
    "readiness": (zod_keys("Readiness"), export["rollups"][0]["readiness"]),
    # Soreness is built from the muscleGroups tuple rather than written out.
    "soreness": (string_array("muscleGroups"),
                 export["rollups"][0]["checkIn"]["soreness"]),
    "timeInZonesMinutes": (zod_keys("TimeInZonesMinutes"),
                           export["rollups"][0]["training"]["workouts"][0]["timeInZonesMinutes"]),
    "workout": (zod_keys("Workout"),
                export["rollups"][0]["training"]["workouts"][0]),
    "topSet": (zod_keys("TopSet"), export["rollups"][0]["training"]["topSets"][0]),
    "goalSettings body": (zod_keys("GoalSettingsBody"), export["documents"]["goalSettings"]),
    "targets": (zod_keys("Targets"), export["documents"]["goalSettings"]["targets"]),
    "program body": (zod_keys("ProgramBody"), export["documents"]["program"]),
    "flags body": (zod_keys("FlagsBody"), export["documents"]["flags"]),
}
# Document bodies: the edge keeps version/updatedAt/updatedBy as table columns, the
# export carries them inline, so they are expected extras there.
envelope = {"version", "updatedAt", "updatedBy"}

ok = True
for name, (expected, actual) in checks.items():
    exp, act = set(expected), set(actual)
    extra = act - exp - (envelope if "body" in name or name == "goalSettings body" else set())
    missing = exp - act
    status = "OK  " if not extra and not missing else "FAIL"
    if status == "FAIL": ok = False
    print(f"{status} {name}: {len(exp)} contract fields")
    if missing: print(f"       missing from export: {sorted(missing)}")
    if extra:   print(f"       not in contract:     {sorted(extra)}")

# The per-entity projections must repeat the rollup's own names, plus `date`.
for key, source in [("workouts", "workout"), ("topSets", "topSet")]:
    expected = set(checks[source][0]) | {"date"}
    actual = set(export[key][0])
    status = "OK  " if actual == expected else "FAIL"
    if status == "FAIL": ok = False
    print(f"{status} {key}[] projection = contract fields + date")
    if actual != expected: print(f"       diff: {sorted(actual ^ expected)}")

# CSV headers must be the JSON field names.
csv_dir = root / "packages/ExportKit/Tests/ExportKitTests/Golden"
for entity in ["meals", "topSets", "sleep", "weight", "readiness"]:
    header = (csv_dir / f"{entity}.expected.csv").read_text().split("\n")[0].split(",")
    json_keys = list(export[entity][0]) if export[entity] else []
    flat = [h for h in header if "." not in h]
    missing = set(flat) - set(json_keys)
    status = "OK  " if not missing else "FAIL"
    if status == "FAIL": ok = False
    print(f"{status} {entity}.csv header ⊆ JSON field names")
    if missing: print(f"       csv-only columns: {sorted(missing)}")

print("\nSCHEMA_VERSION in contract.ts:",
      re.search(r"SCHEMA_VERSION = (\d+)", ts).group(1),
      "| export.json schemaVersion:", export["schemaVersion"])
sys.exit(0 if ok else 1)
