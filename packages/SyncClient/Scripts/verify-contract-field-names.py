"""Compare the request bodies SyncClient sends against `edge/src/contract.ts`.

`docs/EXPORT_SCHEMA.md` is the prose contract; `edge/src/contract.ts` is the only place
those names live on the edge; and the goldens under
`packages/SyncClient/Tests/SyncClientTests/Golden/` are exactly what this client puts on
the wire. The two halves are in different languages, so a rename on either side compiles
cleanly and fails on the first real sync as `contract_violation`. This reads both and
diffs them.

    python3 packages/SyncClient/Scripts/verify-contract-field-names.py .

Run it from the repo root, after the goldens are current:

    ASCENSION_UPDATE_GOLDEN=1 swift test --package-path packages/SyncClient

Exits non-zero on a divergence and names the offending fields. Deliberately not in CI:
`edge/` is a separate job, and this is a cross-language check a reviewer runs once per
contract change — the same arrangement as ExportKit's copy, whose zod reader this shares.
"""
import json, re, sys, pathlib

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
ts = (root / "edge/src/contract.ts").read_text()
golden = root / "packages/SyncClient/Tests/SyncClientTests/Golden"
ingest = json.loads((golden / "ingest.request.json").read_text())
documents = json.loads((golden / "documents.put.json").read_text())
ack = json.loads((golden / "mutations.ack.json").read_text())
enums = json.loads((golden / "enums.json").read_text())
schema_md = (root / "docs/EXPORT_SCHEMA.md").read_text()


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


ok = True


def check(name, expected, actual, allow_extra=frozenset()):
    global ok
    exp, act = set(expected), set(actual)
    extra, missing = act - exp - set(allow_extra), exp - act
    status = "OK  " if not extra and not missing else "FAIL"
    if status == "FAIL": ok = False
    print(f"{status} {name}: {len(exp)} contract fields")
    if missing: print(f"       missing from the request: {sorted(missing)}")
    if extra:   print(f"       not in the contract:      {sorted(extra)}")


print("== POST /v1/ingest ==")
rollup = ingest["rollups"][0]
check("IngestEnvelope", zod_keys("IngestEnvelope"), ingest)
check("DayRollup", zod_keys("DayRollup"), rollup)
for group in ["nutrition", "activity", "sleep", "vitals", "body", "training"]:
    check(group, zod_keys(group.capitalize()), rollup[group])
check("wins", zod_keys("Wins"), rollup["wins"])
check("checkIn", zod_keys("CheckIn"), rollup["checkIn"])
check("readiness", zod_keys("Readiness"), rollup["readiness"])
check("checkIn.soreness", string_array("muscleGroups"), rollup["checkIn"]["soreness"])
workout = rollup["training"]["workouts"][0]
check("training.workouts[]", zod_keys("Workout"), workout)
check("workout.timeInZonesMinutes", zod_keys("TimeInZonesMinutes"),
      workout["timeInZonesMinutes"])
check("training.topSets[]", zod_keys("TopSet"), rollup["training"]["topSets"][0])

# A zod `.nullable()` that is not `.optional()` rejects a missing key, so every
# measurement must be present even when it was not measured.
missing_nulls = [key for key in zod_keys("Body") if key not in rollup["body"]]
status = "OK  " if not missing_nulls else "FAIL"
if missing_nulls: ok = False
print(f"{status} unmeasured fields are explicit nulls, not omitted keys")
if missing_nulls: print(f"       omitted: {sorted(missing_nulls)}")

print("\n== PUT /v1/documents/<key> ==")
# The edge keeps version/updatedAt/updatedBy as columns on the `documents` table and
# composes them back on read, so a PUT body must carry none of them.
envelope = {"version", "updatedAt", "updatedBy", "schemaVersion", "key"}
for key, schema in [("goalSettings", "GoalSettingsBody"), ("program", "ProgramBody"),
                    ("flags", "FlagsBody")]:
    check(f"{key} body", zod_keys(schema), documents[key])
    leaked = envelope & set(documents[key])
    if leaked:
        ok = False
        print(f"FAIL {key} body carries envelope keys: {sorted(leaked)}")
    else:
        print(f"OK   {key} body carries no envelope keys")
check("goalSettings.targets", zod_keys("Targets"), documents["goalSettings"]["targets"])
check("program.days[]", ["weekday", "kind"], documents["program"]["days"][0])

print("\n== closed sets ==")
for name, contract_name in [("sessionKinds", "sessionKinds"), ("verdicts", "verdicts"),
                            ("sorenessLevels", "sorenessLevels"),
                            ("muscleGroups", "muscleGroups"), ("actors", "actors"),
                            ("documentKeys", "documentKeys"), ("mealSlots", "mealSlots")]:
    expected, actual = string_array(contract_name), enums[name]
    status = "OK  " if expected == actual else "FAIL"
    if status == "FAIL": ok = False
    print(f"{status} {name}: {len(expected)} values, same order")
    if expected != actual:
        print(f"       contract: {expected}\n       client:   {actual}")

# `museWriteMode` is an inline enum on FlagsBody rather than an exported tuple.
modes = re.search(r'museWriteMode: z\.enum\(\[(.*?)\]\)', ts, re.S).group(1)
modes = re.findall(r'"(\w+)"', modes)
status = "OK  " if modes == enums["museWriteModes"] else "FAIL"
if status == "FAIL": ok = False
print(f"{status} museWriteModes: {modes}")

# contract.ts has no mutation-kind list yet (ASC-13 owns the write tools), so the kinds
# are checked against the §3 table in the prose contract instead.
table = re.search(r"### Kinds(.*?)\n\n`meal`", schema_md, re.S).group(1)
kinds = re.findall(r"^\| `(\w+)` \|", table, re.M)
status = "OK  " if kinds == enums["mutationKinds"] else "FAIL"
if status == "FAIL": ok = False
print(f"{status} mutationKinds: {len(kinds)} kinds from EXPORT_SCHEMA.md §3, same order")
if kinds != enums["mutationKinds"]:
    print(f"       doc:    {kinds}\n       client: {enums['mutationKinds']}")

print("\n== POST /v1/mutations/ack ==")
# No zod schema on the edge yet: ASC-13 owns this endpoint. Printed so the Worker's
# author matches it rather than guessing.
print("NOTE ack body keys:", sorted(ack), "— edge/ has no schema for these yet (ASC-13)")

print("\nSCHEMA_VERSION in contract.ts:",
      re.search(r"SCHEMA_VERSION = (\d+)", ts).group(1),
      "| ingest.request.json schemaVersion:", ingest["schemaVersion"])
sys.exit(0 if ok else 1)
