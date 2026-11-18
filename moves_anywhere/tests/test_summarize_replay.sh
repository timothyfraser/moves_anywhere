#!/bin/bash
# test_summarize_replay.sh ####################################################
#
# What:      tests/test_summarize_replay.sh: replays the summary step (task_summarize.R) from saved MOVES outputs. No MOVES run.
# Does:      Copies each case into a fresh temp folder, runs only task_summarize.R in the image with this
#            checkout's scripts/ mounted read-only over /cat/scripts, and checks exit code and diagnostics.txt.
#            1. county run with no population rows (saved outputs): exit 0, two exact lines, population NA.
#            2. county gold (inputs_ny): exit 0, CO2e 358162.4, population 62546.5.
#            3. project gold (inputs_project, its link.csv as _link.csv): exit 0, header line, one row per link.
#            --prove also runs case 1 against the image's own script (no mount) and expects exit 1.
# Called by: Developer tool. Not run by launch.sh.
# Reads:     tests/fixtures/replay/county_hour_no_population/, inputs_ny/, inputs_project/, scripts/
# Writes:    a temporary folder, removed on exit unless --keep
# Exits:     the number of failed checks (0 = all passed); 2 on a usage or setup error
# Usage: bash moves_anywhere/tests/test_summarize_replay.sh [--image <name:tag>] [--prove] [--keep]
# Needs Docker and the image (default tmf77/moves-anywhere:v3.1.0). The image's script is at /cat/scripts.
#   The default stays 3.1.0 on purpose: --prove needs the unpatched script, which only the 3.1.0 image still has.
###############################################################################

IMAGE="${IMAGE:-tmf77/moves-anywhere:v3.1.0}"; PROVE=0; KEEP=0
usage() { echo "usage: $0 [--image <name:tag>] [--prove] [--keep]"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --image) [ $# -ge 2 ] || { usage >&2; exit 2; }; IMAGE="$2"; shift 2 ;;
    --prove) PROVE=1; shift ;;
    --keep) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MA="$(cd "$here/.." && pwd)"
FIX="$MA/tests/fixtures/replay/county_hour_no_population"
NY="$MA/inputs_ny"; PRJ="$MA/inputs_project"; SCRIPTS="$MA/scripts"
for p in "$FIX/movesoutput.csv.gz" "$FIX/movesactivityoutput.csv.gz" "$FIX/rs_custom.xml" \
         "$NY/movesoutput.csv" "$NY/movesactivityoutput.csv" "$NY/rs_custom.xml" \
         "$PRJ/linkdata.csv" "$PRJ/link.csv" "$PRJ/movesoutput.csv" "$PRJ/movesactivityoutput.csv" "$PRJ/rs_custom.xml"; do
  [ -f "$p" ] || { echo "fixture not found: $p" >&2; exit 2; }
done

FAILS=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILS=$((FAILS + 1)); fi; }

TMP=$(mktemp -d)
# Native Windows programs (docker) need C:/... rather than /tmp/...
command -v cygpath >/dev/null 2>&1 && TMP=$(cygpath -m "$TMP")
cleanup() { [ "$KEEP" = 1 ] && echo "kept: $TMP" || rm -rf "$TMP"; }
trap cleanup EXIT
MOUNT_SCRIPTS="$SCRIPTS"
command -v cygpath >/dev/null 2>&1 && MOUNT_SCRIPTS=$(cygpath -m "$SCRIPTS")

# run_summary <case> <folder> <patched 1|0>: runs the step; sets RC; log in <folder>.log
run_summary() {
  local name=$1 dir=$2 patched=$3 mount=()
  [ "$patched" = 1 ] && mount=(-v "$MOUNT_SCRIPTS:/cat/scripts:ro")
  MSYS_NO_PATHCONV=1 timeout 120 docker run --rm --name "w21-$name" -v "$dir:/cat/inputs" "${mount[@]}" \
    --entrypoint Rscript "$IMAGE" /cat/scripts/task_summarize.R > "$dir.log" 2>&1
  RC=$?
}

# Case 1: no population rows
C1="$TMP/c1"; mkdir -p "$C1"
cp "$FIX/rs_custom.xml" "$C1/"; gzip -dc "$FIX/movesoutput.csv.gz" > "$C1/movesoutput.csv"
gzip -dc "$FIX/movesactivityoutput.csv.gz" > "$C1/movesactivityoutput.csv"
run_summary c1 "$C1" 1
check "case 1 (no population rows): exit 0" "[ $RC -eq 0 ]"
check "case 1: diagnostics.txt is exactly the two expected lines" \
  "[ \"\$(tr -d '\r' < '$C1/diagnostics.txt' 2>/dev/null)\" = \"\$(printf 'CO2e Emissions (98): 43596021.3\nVehicle Population: NA')\" ]"

# Case 2: county gold
C2="$TMP/c2"; mkdir -p "$C2"
cp "$NY/rs_custom.xml" "$NY/movesoutput.csv" "$NY/movesactivityoutput.csv" "$C2/"
run_summary c2 "$C2" 1
check "case 2 (county gold): exit 0" "[ $RC -eq 0 ]"
check "case 2: diagnostics.txt is CO2e 358162.4 and population 62546.5" \
  "[ \"\$(tr -d '\r' < '$C2/diagnostics.txt' 2>/dev/null)\" = \"\$(printf 'CO2e Emissions (98): 358162.4\nVehicle Population: 62546.5')\" ]"

# Case 3: project gold (the run's _link.csv is the user's link.csv; no _project_inputs.csv needed)
C3="$TMP/c3"; mkdir -p "$C3"
cp "$PRJ/rs_custom.xml" "$PRJ/linkdata.csv" "$PRJ/movesoutput.csv" "$PRJ/movesactivityoutput.csv" "$C3/"
cp "$PRJ/link.csv" "$C3/_link.csv"
run_summary c3 "$C3" 1
nlinks=$(( $(tr -d '\r' < "$PRJ/link.csv" | grep -c .) - 1 ))
check "case 3 (project gold): exit 0" "[ $RC -eq 0 ]"
check "case 3: header line, column row, one row per link" \
  "[ \"\$(head -n 1 '$C3/diagnostics.txt' 2>/dev/null | tr -d '\r')\" = 'Project-scale run: one hour, results by link (grams, miles)' ] && [ \"\$(tr -d '\r' < '$C3/diagnostics.txt' | grep -c '^[0-9]')\" -eq $nlinks ]"

# Optional: the released image's own script must still fail on case 1 (proves the test sees the bug)
if [ "$PROVE" = 1 ]; then
  P1="$TMP/p1"; mkdir -p "$P1"
  cp "$C1/rs_custom.xml" "$C1/movesoutput.csv" "$C1/movesactivityoutput.csv" "$P1/"
  run_summary p1 "$P1" 0
  check "prove: image's own unpatched script exits 1 on case 1" "[ $RC -eq 1 ]"
  check "prove: the error is round(a, 1)" "grep -q 'round(a, 1)' '$P1.log'"
fi

echo "----"; echo "failed checks: $FAILS"
exit $FAILS
