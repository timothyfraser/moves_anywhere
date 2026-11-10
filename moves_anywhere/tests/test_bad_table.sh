#!/bin/bash
# test_bad_table.sh ###########################################################
#
# What:      tests/test_bad_table.sh <image>: proves a bad input table stops the run at the adapt step.
# Does:      Copies moves_anywhere/inputs_ny to a temporary folder, replaces sourcetypeyear.csv there with
#            a table whose columns are wrong, runs the image in mounted mode through run.sh, and checks
#            the exit status, the failed manifest, and a stop_reason that starts "adapt failed on sourcetypeyear".
# Called by: Developer tool: test of the exit-status handling of launch.sh (CM-8.18). Not run by launch.sh.
# Reads:     moves_anywhere/inputs_ny, moves_anywhere/run.sh, tests/manifest_get.py; needs Docker and the image
# Writes:    a temporary folder, removed on exit
# Exits:     2 if the image argument is missing; 0 if every check passes, 1 otherwise
###############################################################################

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
image="${1:-}"
[ -n "$image" ] || { echo "usage: test_bad_table.sh <image>" >&2; exit 2; }

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS  $1"; }
bad() { fail=$((fail+1)); echo "FAIL  $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# 1. Make a copy of the inputs with one bad table ####
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
D="$tmp/inputs"
mkdir -p "$D" && cp "$repo/moves_anywhere/inputs_ny"/* "$D"/
# Remove the finished-run outputs so nothing from the fixture can stand in for a new result.
rm -f "$D"/data.csv "$D"/movesoutput.csv "$D"/movesactivityoutput.csv "$D"/moveslog.txt "$D"/diagnostics.txt \
      "$D"/run_manifest.json "$D"/data.csv.gz "$D"/moveslog.txt.gz
printf 'not_a_column,another_bad_one\n1,2\n' > "$D/sourcetypeyear.csv"

# 2. Run the image the way a user does ####
bash "$repo/moves_anywhere/run.sh" "$D" --image "$image" > "$tmp/run.log" 2>&1
rc=$?
tail -n 5 "$tmp/run.log" | sed 's/^/      /'

# 3. Check the result ####
check "run exits non-zero (got $rc)" "[ $rc -ne 0 ]"
man="$D/run_manifest.json"
status=""; reason=""
if [ -f "$man" ]; then
  status="$(python3 -I "$here/manifest_get.py" "$man" status)"
  reason="$(python3 -I "$here/manifest_get.py" "$man" stop_reason)"
fi
check "run_manifest.json exists and status is failed (got '$status')" "[ '$status' = failed ]"
case "$reason" in
  "adapt failed on sourcetypeyear"*) check "stop_reason starts 'adapt failed on sourcetypeyear'" "true" ;;
  *) check "stop_reason starts 'adapt failed on sourcetypeyear' (got '$reason')" "false" ;;
esac

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
