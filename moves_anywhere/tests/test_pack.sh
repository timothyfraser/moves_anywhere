#!/bin/bash
# tests/test_pack.sh: proves scripts/task_pack.sh on a finished run folder, without running MOVES.
# Usage: bash moves_anywhere/tests/test_pack.sh [FIXTURE_DIR]
# FIXTURE_DIR defaults to $PACK_FIXTURE, else moves_anywhere/inputs_ny (a finished run, 47
# files, in this repository). The fixture is copied; it is never modified.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pack="$here/../scripts/task_pack.sh"
export TP_REPO="$(cd "$here/../.." && pwd)"
fixture="${1:-${PACK_FIXTURE:-$TP_REPO/moves_anywhere/inputs_ny}}"
[ -d "$fixture" ] || { echo "fixture folder not found: $fixture" >&2; exit 2; }

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS  $1"; }
bad() { fail=$((fail+1)); echo "FAIL  $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
D="$tmp/inputs"
mkdir -p "$D" && cp "$fixture"/* "$D"/
gzip -c "$fixture/data.csv"     > "$D/data.csv.gz"
gzip -c "$fixture/moveslog.txt" > "$D/moveslog.txt.gz"
printf 'check_inputs 0\nadapt 41\nmoves 1544\npostprocess 63\n' > "$D/.timings"

digest="sha256:$(printf 'ab%.0s' $(seq 32))"
export INPUTS_DIR="$D" RUN_ID=d36109-u1-o1 MOVES_IMAGE=moves-anywhere:test \
  MOVES_IMAGE_DIGEST="$digest" MOVES_COMMIT=3e5a7c9 \
  MOVES_DIR="$tmp/no-such-dir" RUN_STARTED_AT=2026-11-02T19:16:02Z
unset RUN_STATUS RUN_STOP_REASON MOVES_DEBUG

# Source it, as the launcher does.
( . "$pack" ); rc1=$?
check "sourced run exits 0" "[ $rc1 -eq 0 ]"
sha1="$(sha256sum "$D/replication.tar.xz" | cut -d' ' -f1)"
cp "$D/run_manifest.json" "$tmp/manifest1.json"
( . "$pack" ); rc2=$?
check "second run exits 0" "[ $rc2 -eq 0 ]"
sha2="$(sha256sum "$D/replication.tar.xz" | cut -d' ' -f1)"
check "tar sha256 equal across two runs" "[ '$sha1' = '$sha2' ]"
echo "      run 1 sha256: $sha1"
echo "      run 2 sha256: $sha2"
check "no stray files left (kit/, .part)" "[ ! -e '$D/kit' ] && ! ls '$D'/*.part >/dev/null 2>&1"

kit_bytes=$(wc -c < "$D/replication.tar.xz" | tr -d ' ')
echo "      kit size: $kit_bytes bytes ($(python3 -c "print(round($kit_bytes/1048576,2))") MiB)"
check "kit size plausible (1 MB to 20 MB)" "[ $kit_bytes -gt 1000000 ] && [ $kit_bytes -lt 20000000 ]"

# Manifest content, checked independently of the packer.
python3 -I - "$D" "$tmp/manifest1.json" "$TP_REPO" <<'PYEOF'
#!/usr/bin/env python3
"""Independent checks of run_manifest.json for tests/test_pack.sh.

Usage: check_manifest.py <inputs_dir> <first_run_manifest_copy> <repo_root>
Recomputes every size and checksum itself; shares no code with the packer.
"""
import hashlib
import json
import os
import re
import sys

D, first, repo = sys.argv[1], sys.argv[2], sys.argv[3]
res = []


def t(name, cond):
    res.append((name, bool(cond)))


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def path(n):
    return os.path.join(D, n)


try:
    with open(path("run_manifest.json"), encoding="utf-8") as fh:
        m = json.load(fh)
    t("manifest loads", True)
except Exception as e:  # noqa: BLE001
    print("FAIL  manifest loads:", e)
    sys.exit(1)
with open(first, encoding="utf-8") as fh:
    m1 = json.load(fh)

req = ["manifest_version", "run_id", "status", "stop_reason", "mode", "image", "moves",
       "runspec", "inputs", "outputs", "timings", "started_at", "finished_at", "host"]
t("required fields present, nothing extra", sorted(m) == sorted(req))
t("status ok, stop_reason", m["status"] == "ok" and m["stop_reason"] == "MOVES finished")
t("run_id and mode", m["run_id"] == "d36109-u1-o1" and m["mode"] == "inv")
t("image block", m["image"]["name"] == "moves-anywhere:test"
  and re.fullmatch(r"sha256:[0-9a-f]{64}", m["image"]["digest"]))
t("moves block", m["moves"] == {"commit": "3e5a7c9", "default_db": "movesdb20241112"})
t("runspec from parameters.json", m["runspec"] == {
    "geoid": "36109", "year": 2022, "mode": "inv", "geoaggregation": "county",
    "timeaggregation": "year", "debug": False,
    "pollutants": [90, 98, 2, 118, 112, 119, 5, 33, 32, 6, 3, 100, 110, 106, 107, 116, 117, 115, 31, 91, 1]})
t("timings from .timings plus pack", m["timings"].get("adapt") == 41
  and m["timings"].get("moves") == 1544 and "pack" in m["timings"])
t("started_at as given, finished_at set", m["started_at"] == "2026-11-02T19:16:02Z"
  and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", m["finished_at"]))
t("host", m["host"]["cpus"] >= 1 and m["host"]["mem_bytes"] >= 0)
t("outputs are exactly the three present D27 objects",
  [o["name"] for o in m["outputs"]] == ["data.csv.gz", "moveslog.txt.gz", "replication.tar.xz"])
t("outputs bytes and sha256 match recomputation",
  all(o["bytes"] == os.path.getsize(path(o["name"])) and o["sha256"] == sha(path(o["name"]))
      for o in m["outputs"]))
t("manifest does not list itself", all(o["name"] != "run_manifest.json" for o in m["outputs"]))
user = sorted(f for f in os.listdir(D) if f.endswith(".csv") and not f.startswith("_")
              and f not in ("data.csv", "movesoutput.csv", "movesactivityoutput.csv"))
t("inputs = user csv + runspec + parameters (no adapted _*.csv)",
  [i["name"] for i in m["inputs"]] == sorted(user + ["parameters.json", "rs_custom.xml"]))
t("inputs bytes and sha256 match recomputation",
  all(i["bytes"] == os.path.getsize(path(i["name"])) and i["sha256"] == sha(path(i["name"]))
      for i in m["inputs"]))
t("manifest identical across runs except finished_at and timings",
  all(m[k] == m1[k] for k in m if k not in ("finished_at", "timings")))
try:
    import jsonschema
    with open(os.path.join(repo, "docs", "RUN_MANIFEST.md"), encoding="utf-8") as fh:
        md = fh.read()
    schema = json.loads(re.search(r"```json\n(.*?)\n```", md[md.find("JSON Schema"):], re.S).group(1))
    jsonschema.Draft7Validator(schema).validate(m)
    t("validates against the schema block in docs/RUN_MANIFEST.md (jsonschema)", True)
except ImportError:
    print("SKIP  jsonschema not installed; the packer used structural checks")

for name, cond in res:
    print(("PASS  " if cond else "FAIL  ") + name)
sys.exit(0 if all(c for _, c in res) else 1)
PYEOF
py_rc=$?
[ $py_rc -eq 0 ] && ok "manifest checks (the lines above)" || bad "manifest checks (see FAIL lines above)"

# Kit members.
tar -tJf "$D/replication.tar.xz" > "$tmp/members_raw.txt"
sort "$tmp/members_raw.txt" > "$tmp/members.txt"
echo "      kit members: $(wc -l < "$tmp/members.txt")"
exp="$tmp/expected.txt"
{ for f in rs_custom.xml parameters.json movesoutput.csv movesactivityoutput.csv diagnostics.txt moveslog.txt kit/README.txt kit/importer.xml; do echo "$f"; done
  (cd "$D" && ls *.csv | grep -v -x -e data.csv -e movesoutput.csv -e movesactivityoutput.csv)
} | sort -u > "$exp"
check "kit lists exactly the expected members" "diff -q '$exp' '$tmp/members.txt' >/dev/null"
check "kit excludes data.csv(.gz), moveslog.txt.gz, manifest, .timings, the tar, .part" \
  "! grep -E '^(data\.csv(\.gz)?|moveslog\.txt\.gz|run_manifest\.json|\.timings|replication\.tar\.xz)$|\.part$' '$tmp/members.txt' >/dev/null"
check "kit tar is in sorted name order" "cmp -s '$tmp/members_raw.txt' <(LC_ALL=C sort '$tmp/members_raw.txt')"
mkdir "$tmp/x" && tar -xJf "$D/replication.tar.xz" -C "$tmp/x"
check "kit/importer.xml has no /cat/ path" "! grep -q '/cat/' '$tmp/x/kit/importer.xml'"
check "kit/importer.xml uses ./_name.csv paths" "grep -q '<filename>\./_sourcetypeagedistribution.csv</filename>' '$tmp/x/kit/importer.xml'"
check "kit/README.txt present and mentions importer" "grep -q 'importer' '$tmp/x/kit/README.txt'"
check "kit files are byte-identical to the originals" \
  "cmp -s '$D/movesoutput.csv' '$tmp/x/movesoutput.csv' && cmp -s '$D/_zone.csv' '$tmp/x/_zone.csv' && cmp -s '$D/rs_custom.xml' '$tmp/x/rs_custom.xml'"
check "failed-run manifest: RUN_STATUS=failed is carried" \
  "( export RUN_STATUS=failed RUN_STOP_REASON='MOVES exited 1: see moveslog.txt.gz'; . '$pack' ) && grep -q '\"status\": \"failed\"' '$D/run_manifest.json' && grep -q 'MOVES exited 1' '$D/run_manifest.json'"

echo "----"; echo "passed: $pass  failed: $fail"
[ $fail -eq 0 ]
