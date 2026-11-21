#!/bin/bash
# test_pack_project.sh ########################################################
#
# What:      tests/test_pack_project.sh: proves the pack step for a project-scale run, without MOVES or Docker.
# Does:      Copies inputs_project/ to a temp folder, adds a fake linkdata.csv and the two MOVES outputs,
#            gzips them as task_compress_outputs.sh would, packs, and checks the manifest: status ok,
#            mode inv, linkdata.csv.gz listed, data.csv.gz not listed, user link tables in inputs.
#            Then removes linkdata.csv(.gz), packs again, and checks status failed.
# Called by: Developer tool. Not run by launch.sh.
# Reads:     moves_anywhere/inputs_project/, scripts/task_pack.sh, tests/manifest_get.py
# Writes:    a temporary folder, removed on exit
# Exits:     0 if every check passes, 1 otherwise
# Usage: bash moves_anywhere/tests/test_pack_project.sh
# task_compress_outputs.sh works in /cat, so this test gzips the files itself the same way
# (gzip -c f > f.gz); the compress script is covered by bash -n and by the real image.
###############################################################################

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pack="$here/../scripts/task_pack.sh"
fixture="$here/../inputs_project"
[ -d "$fixture" ] || { echo "fixture folder not found: $fixture" >&2; exit 2; }

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS  $1"; }
bad() { fail=$((fail+1)); echo "FAIL  $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
D="$tmp/inputs"
mkdir -p "$D" && cp "$fixture"/* "$D"/
printf 'linkID,pollutantID,emissionQuant\n1,90,1.5\n' > "$D/linkdata.csv"
printf 'a,b\n1,2\n' > "$D/movesoutput.csv"
printf 'a,b\n1,2\n' > "$D/movesactivityoutput.csv"
gzip -c "$D/linkdata.csv" > "$D/linkdata.csv.gz"
printf 'check_inputs 0\nadapt 1\nmoves 2\n' > "$D/.timings"

export INPUTS_DIR="$D" RUN_ID=d36109-u1-o1 MOVES_IMAGE=moves-anywhere:test MOVES_DIR="$tmp/no-such-dir" \
  RUN_STARTED_AT=2026-11-17T12:00:00Z RUN_STATUS=ok RUN_STOP_REASON='MOVES finished'
unset MOVES_DEBUG
get() { python3 -I "$here/manifest_get.py" "$D/run_manifest.json" "$1" | tr -d '\r'; }

( . "$pack" ) >/dev/null 2>&1
check "manifest status is ok" "[ \"\$(get status)\" = ok ]"
check "manifest mode is inv" "[ \"\$(get mode)\" = inv ]"
check "outputs list linkdata.csv.gz" "grep -q '\"name\": \"linkdata.csv.gz\"' '$D/run_manifest.json'"
check "outputs do not list data.csv.gz" "! grep -q '\"name\": \"data.csv.gz\"' '$D/run_manifest.json'"
check "inputs list link.csv" "grep -q '\"name\": \"link.csv\"' '$D/run_manifest.json'"
check "inputs do not list linkdata.csv" "! python3 -I -c 'import json,sys; sys.exit(0 if any(i[\"name\"]==\"linkdata.csv\" for i in json.load(open(sys.argv[1]))[\"inputs\"]) else 1)' '$D/run_manifest.json'"

rm -f "$D/linkdata.csv" "$D/linkdata.csv.gz" "$D/run_manifest.json"
( . "$pack" ) >/dev/null 2>&1
check "no linkdata.csv: status failed" "[ \"\$(get status)\" = failed ]"
check "no linkdata.csv: reason names the missing results" "grep -q 'produced no results' '$D/run_manifest.json'"

echo "----"; echo "passed: $pass  failed: $fail"
[ $fail -eq 0 ]
