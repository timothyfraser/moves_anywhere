#!/bin/bash
# test_epa_project.sh #########################################################
#
# What:      Proves a project-scale run reproduces EPA's own training exercise (MOVES5 Module 7 answer key).
# Does:      Copies the inputs of inputs_epa_project/ (without epa_*.csv, README.md and
#            driveschedulesecondlink_run2.csv) to a temp folder, runs run.sh with --image, then checks:
#            exit 0, run_manifest.json status ok, linkdata.csv (or .gz) present, no data.csv, and that
#            movesoutput.csv matches EPA's run 1 within 1% (compare_epa_project.py).
#            With --run2: a second run with driveschedulesecondlink_run2.csv copied in as
#            driveschedulesecondlink.csv, compared with EPA's run 2.
#            One container at a time. Each run takes under 10 minutes of MOVES.
# Called by: tests/run_gate.sh (step epa). Also run by hand.
# Reads:     moves_anywhere/inputs_epa_project/, run.sh, tests/compare_epa_project.py, tests/manifest_get.py
# Writes:    temporary run folders, removed on exit unless --keep
# Exits:     the number of failed checks (0 = all passed); 2 on a usage error or if not in a git repository
# Usage: bash moves_anywhere/tests/test_epa_project.sh [--image <name:tag>] [--run2] [--keep]
# Needs Docker and the image (--image, or IMAGE, default tmf77/moves-anywhere:v3).
###############################################################################

SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
REPO=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "test_epa_project.sh: not in a git repository" >&2; exit 2; }
cd "$REPO" || exit 2
IMAGE=${IMAGE:-tmf77/moves-anywhere:v3}
RUN2=0; KEEP=0
usage() { sed -n '2,17p' "$SELF" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --image) [ $# -ge 2 ] || { usage >&2; exit 2; }; IMAGE="$2"; shift 2 ;;
    --run2) RUN2=1; shift ;;
    --keep) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "test_epa_project.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
done

FIXTURE="$REPO/moves_anywhere/inputs_epa_project"
RUN_SH="moves_anywhere/run.sh"
COMPARE="moves_anywhere/tests/compare_epa_project.py"
FAILS=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILS=$((FAILS + 1)); fi; }

TMP=$(mktemp -d)
# Native Windows programs (python, docker) need C:/... rather than /tmp/...
command -v cygpath >/dev/null 2>&1 && TMP=$(cygpath -m "$TMP")
cleanup() { [ "$KEEP" = 1 ] && echo "kept: $TMP" || rm -rf "$TMP"; }
trap cleanup EXIT

# 1. Helpers ####
# fresh_copy <dir>: the fixture's input files only (no EPA answer files, README, or the run 2 schedule)
fresh_copy() {
  local d=$1 f b
  rm -rf "$d"; mkdir -p "$d"
  for f in "$FIXTURE"/*; do
    [ -f "$f" ] || continue   # workbook_only/ holds tables EPA's run did not read
    b=$(basename "$f")
    case "$b" in epa_*.csv|README.md|driveschedulesecondlink_run2.csv) continue ;; esac
    cp "$f" "$d/" || { echo "cannot copy $b"; return 1; }
  done
}
# run_in <dir> <log>: run.sh on the folder; the status is returned, all output goes to the log and the screen
run_in() { bash "$RUN_SH" "$1" --image "$IMAGE" > "$2" 2>&1; local rc=$?; tail -n 5 "$2"; return $rc; }
mget() { python3 -I -B "$REPO/moves_anywhere/tests/manifest_get.py" "$1/run_manifest.json" "$2" 2>/dev/null | tr -d '\r'; }
# has_out <dir> <name>: the output is in the folder, plain or compressed
has_out() { [ -e "$1/$2" ] || [ -e "$1/$2.gz" ]; }
# plain_out <run dir> <name>: the output as plain .csv (expands .gz if that is all the run left)
plain_out() {
  if [ -f "$1/$2" ]; then return 0; fi
  [ -f "$1/$2.gz" ] && gzip -dc "$1/$2.gz" > "$1/$2"
}
# compare_epa <run dir> <epa run id>
compare_epa() {
  plain_out "$1" movesoutput.csv || { echo "movesoutput.csv missing"; return 1; }
  python -I -B "$COMPARE" "$FIXTURE/epa_movesoutput.csv" "$1/movesoutput.csv" --run "$2" --tol 0.01 --out "$1/comparison_run$2.csv" | tail -n 25
  return "${PIPESTATUS[0]}"
}
# do_run <label> <epa run id> <dir>: run, then the checks
do_run() {
  local label=$1 id=$2 R=$3 RC
  run_in "$R" "$TMP/$label.log"; RC=$?
  check "$label: run.sh exit status 0 (got $RC)" '[ "$RC" = 0 ]'
  check "$label: manifest status ok (got '$(mget "$R" status)')" '[ "$(mget "$R" status)" = ok ]'
  check "$label: linkdata.csv exists" 'has_out "$R" linkdata.csv'
  check "$label: no data.csv and no data.csv.gz" '[ ! -e "$R/data.csv" ] && [ ! -e "$R/data.csv.gz" ]'
  check "$label: movesoutput.csv within 1% of EPA run $id" 'compare_epa "$R" "$id"'
}

# 2. The runs ####
echo "=== 1. EPA exercise, run 1 (average speeds; under 10 minutes)"
R1="$TMP/run1"
fresh_copy "$R1" || exit 2
do_run "run 1" 1 "$R1"

if [ "$RUN2" = 1 ]; then
  echo "=== 2. EPA exercise, run 2 (drive schedules)"
  R2="$TMP/run2"
  fresh_copy "$R2" || exit 2
  cp "$FIXTURE/driveschedulesecondlink_run2.csv" "$R2/driveschedulesecondlink.csv" || exit 2
  do_run "run 2" 2 "$R2"
fi

echo
if [ "$FAILS" = 0 ]; then echo "PASS: all assertions"; else echo "FAIL: $FAILS assertion(s)"; fi
exit "$FAILS"
