#!/bin/bash
# test_bad_table.sh ###########################################################
#
# What:      Proves a bad input table stops a ticket-mode run at the adapt step and is reported (CM-8.18).
# Does:      Like test_ticket_mode.sh: the stub ticket server runs in a container and the MOVES container
#            joins its network. The stub serves the normal inputs_ny inputs, except sourcetypeyear.csv,
#            which has the wrong columns. Checks the exit status and the failed manifest the run pushes.
# Called by: Developer tool: test of the exit-status handling of launch.sh. Not run by launch.sh.
# Reads:     fixture_dir (or FIXTURE, default moves_anywhere/inputs_ny), tests/ticket_stub_server.py,
#            tests/manifest_get.py
# Writes:    moves_anywhere/tests/.work/bad_table/; strips CR from scripts/*.sh in place
# Exits:     1 if not in a git repository; otherwise the number of failed assertions
# Usage: bash moves_anywhere/tests/test_bad_table.sh [fixture_dir]
# Needs Docker and the image (IMAGE, default tmf77/moves-anywhere:v3).
###############################################################################

export MSYS_NO_PATHCONV=1
REPO=$(git rev-parse --show-toplevel) || exit 1
cd "$REPO" || exit 1
IMAGE=${IMAGE:-tmf77/moves-anywhere:v3}
SCRIPTS="$(pwd -W 2>/dev/null || pwd)/moves_anywhere/scripts"
TESTS="$(pwd -W 2>/dev/null || pwd)/moves_anywhere/tests"
FIXTURE=${1:-${FIXTURE:-$REPO/moves_anywhere/inputs_ny}}
WORK="$REPO/moves_anywhere/tests/.work/bad_table"
FAILS=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILS=$((FAILS + 1)); fi; }

for f in "$REPO"/moves_anywhere/scripts/*.sh; do sed -i 's/\r$//' "$f"; done

# 1. Inputs: the 14 user tables + runspec + parameters, with one bad table ####
rm -rf "$WORK"; mkdir -p "$WORK/in" "$WORK/out"
for f in avft avgspeeddistribution dayvmtfraction fuelformulation fuelsupply fuelusagefraction \
         hourvmtfraction imcoverage monthvmtfraction roadtypedistribution sourcetypeagedistribution \
         sourcetypeyear sourcetypeyearvmt zonemonthhour; do cp "$FIXTURE/$f.csv" "$WORK/in/"; done
cp "$FIXTURE/rs_custom.xml" "$FIXTURE/parameters.json" "$WORK/in/"
printf 'not_a_column,another_bad_one\n1,2\n' > "$WORK/in/sourcetypeyear.csv"

# 2. Run the stub and the MOVES container, as test_ticket_mode.sh does ####
W="$(cd "$WORK" && pwd -W 2>/dev/null || pwd)"
docker rm -f ma_stub_bad_table >/dev/null 2>&1
docker run -d --rm --name ma_stub_bad_table --mount "type=bind,src=$TESTS,target=/t,readonly" \
  --mount "type=bind,src=$W,target=/w" --entrypoint python3 "$IMAGE" -I /t/ticket_stub_server.py \
  --in /w/in --out /w/out --log /w/puts.log --port 8765 >/dev/null
sleep 2
docker run --rm --name ma_run_bad_table --cpus 2 --network "container:ma_stub_bad_table" \
  -e MOVES_IO=ticket -e "MOVES_IMAGE=$IMAGE" -e RUN_ID=d36109-u1-o1 -e MOVES_RETRY_SCALE=0 \
  -e "TICKET_URL=http://127.0.0.1:8765/ticket?t=SECRETTOKEN" \
  --mount "type=bind,src=$SCRIPTS,target=/cat/scripts" \
  --entrypoint bash "$IMAGE" -c "./scripts/launch.sh" > "$WORK/container.log" 2>&1
RC=$?
docker rm -f ma_stub_bad_table >/dev/null 2>&1

# 3. Assertions ####
OUT="$WORK/out"
mf() { python3 -I "$REPO/moves_anywhere/tests/manifest_get.py" "$OUT/run_manifest.json" "$1" 2>/dev/null; }
REASON="$(mf stop_reason)"
check "container exit status is non-zero (got $RC)" '[ "$RC" -ne 0 ]'
check "run_manifest.json pushed with status failed (got '$(mf status)')" '[ -s "$OUT/run_manifest.json" ] && [ "$(mf status)" = failed ]'
check "stop_reason starts 'adapt failed on sourcetypeyear' (got '$REASON')" 'case "$REASON" in "adapt failed on sourcetypeyear"*) true ;; *) false ;; esac'
check "stop_reason is at most 110 characters (got ${#REASON})" '[ "${#REASON}" -ge 1 ] && [ "${#REASON}" -le 110 ]'
check "no data.csv.gz pushed" '[ ! -e "$OUT/data.csv.gz" ]'

echo
if [ "$FAILS" = 0 ]; then echo "PASS: all assertions"; else echo "FAIL: $FAILS assertion(s)"; fi
exit "$FAILS"
