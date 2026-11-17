#!/bin/bash
# test_project.sh #############################################################
#
# What:      Proves a project-scale run works end to end in the image, and that bad project inputs are refused.
# Does:      1. Runs inputs_project/ through run.sh: linkdata.csv written, no data.csv, manifest ok, diagnostics
#               say "Project-scale run", outputs match the gold copies exactly (compare_outputs.py --project).
#            2. Runs again in the same folder with a parameters.json added: still no data.csv, same result
#               (so the first run's outputs are not read back as inputs).
#            3. Four refused runs, each in a fresh copy: hour range 8 to 9, link.csv missing, a vehicle mix
#               that sums to 0.9, a road type with no link. Each must exit non-zero, write no linkdata.csv and print its reason.
#            One container at a time. A full fixture run takes about 8 minutes of MOVES; a refusal is quick.
# Called by: tests/run_gate.sh (step project). Also run by hand.
# Reads:     moves_anywhere/inputs_project/ (4 input files + gold linkdata.csv, movesoutput.csv,
#            movesactivityoutput.csv), moves_anywhere/inputs_ny/parameters.json, run.sh, compare_outputs.py
# Writes:    temporary run folders, removed on exit unless --keep
# Exits:     the number of failed checks (0 = all passed); 2 on a usage error or if not in a git repository
# Usage: bash moves_anywhere/tests/test_project.sh [--image <name:tag>] [--skip-rerun] [--only-refusals] [--keep]
# Needs Docker and the image (--image, or IMAGE, default tmf77/moves-anywhere:v3).
###############################################################################

REPO=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "test_project.sh: not in a git repository" >&2; exit 2; }
cd "$REPO" || exit 2
IMAGE=${IMAGE:-tmf77/moves-anywhere:v3}
SKIP_RERUN=0; ONLY_REFUSALS=0; KEEP=0
usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --image) [ $# -ge 2 ] || { usage >&2; exit 2; }; IMAGE="$2"; shift 2 ;;
    --skip-rerun) SKIP_RERUN=1; shift ;;
    --only-refusals) ONLY_REFUSALS=1; shift ;;
    --keep) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "test_project.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
done

FIXTURE="$REPO/moves_anywhere/inputs_project"
NY="$REPO/moves_anywhere/inputs_ny"
RUN_SH="moves_anywhere/run.sh"
GOLD_FILES="linkdata.csv movesoutput.csv movesactivityoutput.csv"
INPUT_FILES="rs_custom.xml link.csv driveschedulesecondlink.csv offnetworklink.csv"
FAILS=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILS=$((FAILS + 1)); fi; }

TMP=$(mktemp -d)
# Native Windows programs (python, docker) need C:/... rather than /tmp/...
command -v cygpath >/dev/null 2>&1 && TMP=$(cygpath -m "$TMP")
cleanup() { [ "$KEEP" = 1 ] && echo "kept: $TMP" || rm -rf "$TMP"; }
trap cleanup EXIT

# 1. Helpers ####
# fresh_copy <dir>: the four user input files only (never the gold outputs)
fresh_copy() {
  local d=$1 f
  rm -rf "$d"; mkdir -p "$d"
  for f in $INPUT_FILES; do cp "$FIXTURE/$f" "$d/" || { echo "missing fixture input $f"; return 1; }; done
}
# run_in <dir> <log>: run.sh on the folder; the status is returned, all output goes to the log and the screen
run_in() { bash "$RUN_SH" "$1" --image "$IMAGE" > "$2" 2>&1; local rc=$?; tail -n 5 "$2"; return $rc; }
# plain_copy <run dir> <out dir>: the three compared files as plain .csv (expands .gz if that is all the run left)
plain_copy() {
  local f
  rm -rf "$2"; mkdir -p "$2"
  for f in $GOLD_FILES; do
    if [ -f "$1/$f" ]; then cp "$1/$f" "$2/$f"
    elif [ -f "$1/$f.gz" ]; then gzip -dc "$1/$f.gz" > "$2/$f"; fi
  done
}
# gold_ok: every gold file is present; names the first missing one
gold_ok() {
  local f
  for f in $GOLD_FILES; do
    [ -f "$FIXTURE/$f" ] || { echo "gold file missing: $f"; return 1; }
  done
}
# compare_gold <run dir> <label>
compare_gold() {
  local out rc
  gold_ok || return 1
  plain_copy "$1" "$TMP/plain_$2"
  out=$(python -I -B moves_anywhere/scripts/compare_outputs.py --project "$FIXTURE" "$TMP/plain_$2"); rc=$?
  printf '%s\n' "$out" | tail -n 12
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q 'OVERALL: PASS'
}
mget() { python3 -I -B "$REPO/moves_anywhere/tests/manifest_get.py" "$1/run_manifest.json" "$2" 2>/dev/null | tr -d '\r'; }
# has_out <dir> <name>: the output is in the folder, plain or compressed
has_out() { [ -e "$1/$2" ] || [ -e "$1/$2.gz" ]; }

# 2. Steps 1 and 2: the real run, then the run repeated in the same folder ####
if [ "$ONLY_REFUSALS" = 0 ]; then
  echo "=== 1. project run on the fixture (about 8 minutes)"
  R="$TMP/run"
  fresh_copy "$R" || exit 2
  run_in "$R" "$TMP/run1.log"; RC=$?
  check "run 1: run.sh exit status 0 (got $RC)" '[ "$RC" = 0 ]'
  check "run 1: linkdata.csv exists" 'has_out "$R" linkdata.csv'
  check "run 1: no data.csv and no data.csv.gz" '[ ! -e "$R/data.csv" ] && [ ! -e "$R/data.csv.gz" ]'
  check "run 1: manifest status ok (got '$(mget "$R" status)')" '[ "$(mget "$R" status)" = ok ]'
  check "run 1: manifest lists linkdata.csv.gz" '[ -n "$(mget "$R" output:linkdata.csv.gz)" ]'
  check "run 1: diagnostics.txt says 'Project-scale run'" 'grep -q "Project-scale run" "$R/diagnostics.txt"'
  check "run 1: outputs equal the gold copies" 'compare_gold "$R" one'

  if [ "$SKIP_RERUN" = 0 ]; then
    echo "=== 2. second run in the same folder, parameters.json added"
    cp "$NY/parameters.json" "$R/" || exit 2
    run_in "$R" "$TMP/run2.log"; RC=$?
    check "run 2: run.sh exit status 0 (got $RC)" '[ "$RC" = 0 ]'
    check "run 2: no data.csv and no data.csv.gz" '[ ! -e "$R/data.csv" ] && [ ! -e "$R/data.csv.gz" ]'
    check "run 2: manifest status ok (got '$(mget "$R" status)')" '[ "$(mget "$R" status)" = ok ]'
    check "run 2: outputs equal the gold copies" 'compare_gold "$R" two'
  fi
fi

# 3. Step 3: four refusals, each in a fresh copy ####
# refuse <label> <expected reason>: the folder $TMP/<label> is already edited; run and check
refuse() {
  local label=$1 reason=$2 d="$TMP/$1" rc
  run_in "$d" "$TMP/$label.log"; rc=$?
  check "refusal $label: non-zero exit (got $rc)" '[ "$rc" -ne 0 ]'
  check "refusal $label: no linkdata.csv" '! has_out "$d" linkdata.csv'
  check "refusal $label: output says '$reason'" 'grep -qF "$reason" "$TMP/$label.log"'
}

echo "=== 3a. refusal: hour range 8 to 9"
fresh_copy "$TMP/hours" || exit 2
sed -i 's/<endhour id="8"\/>/<endhour id="9"\/>/' "$TMP/hours/rs_custom.xml"
check "hours: rs_custom.xml was edited" 'grep -q "<endhour id=\"9\"/>" "$TMP/hours/rs_custom.xml"'
refuse hours "more than one hour (8 to 9)"

echo "=== 3b. refusal: link.csv missing"
fresh_copy "$TMP/nolink" || exit 2
rm -f "$TMP/nolink/link.csv"
refuse nolink "link.csv is missing from the inputs folder"

echo "=== 3c. refusal: vehicle mix sums to 0.9"
fresh_copy "$TMP/mix" || exit 2
printf 'linkID,sourceTypeID,sourceTypeHourFraction\n1,21,0.5\n1,31,0.4\n' > "$TMP/mix/linksourcetypehour.csv"
refuse mix "vehicle mix for link 1 sums to 0.9, not 1"

echo "=== 3d. refusal: a road type in the run file has no link"
fresh_copy "$TMP/road" || exit 2
# Link 4 is the only link on road type 4; the run file still selects road type 4.
grep -v '^4,' "$TMP/road/link.csv" > "$TMP/road/link.tmp" && mv "$TMP/road/link.tmp" "$TMP/road/link.csv"
refuse road "runspec road type 4 has no link in link.csv"

echo
if [ "$FAILS" = 0 ]; then echo "PASS: all assertions"; else echo "FAIL: $FAILS assertion(s)"; fi
exit "$FAILS"
