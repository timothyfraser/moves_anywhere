#!/bin/bash
# test_sync_mode.sh ###########################################################
#
# What:      Proves MOVES_IO=sync end to end through rclone, with an rclone remote of type local.
# Does:      Defines the remote only in env (RCLONE_CONFIG_STORE_TYPE=local), as docs/RUN_TICKET.md section 6
#            says for any remote, and mounts a work folder at /store. Two failure cases first:
#            MOVES_SYNC_REMOTE unset (exit 5) and a remote with no in/ folder (exit 2, nothing pushed).
#            Then a full Tompkins run: inputs fetched from <remote>/in, outputs and run_manifest.json
#            pushed to <remote>/out, data.csv equal to the fixture's reference.
# Called by: Developer tool: test of sync mode (MOVES_IO=sync in launch.sh). Not run by launch.sh.
# Reads:     fixture_dir (or FIXTURE), scripts/compare_outputs.py, tests/manifest_get.py
# Writes:    moves_anywhere/tests/.work/sync/; strips CR from scripts/*.sh in place
# Exits:     1 if not in a git repository; otherwise the number of failed assertions
# Usage: bash moves_anywhere/tests/test_sync_mode.sh [fixture_dir]
# Needs Docker and the image (IMAGE, default tmf77/moves-anywhere:v3).
###############################################################################

export MSYS_NO_PATHCONV=1
REPO=$(git rev-parse --show-toplevel) || exit 1
cd "$REPO" || exit 1
IMAGE=${IMAGE:-tmf77/moves-anywhere:v3}
SCRIPTS="$(pwd -W 2>/dev/null || pwd)/moves_anywhere/scripts"
FIXTURE=${1:-${FIXTURE:-$REPO/moves_anywhere/inputs_ny}}
WORK="$REPO/moves_anywhere/tests/.work/sync"
TESTS_DIR="$REPO/moves_anywhere/tests"
FAILS=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILS=$((FAILS + 1)); fi; }

for f in "$REPO"/moves_anywhere/scripts/*.sh; do sed -i 's/\r$//' "$f"; done

# User inputs only: 14 tables + runspec + parameters (no outputs, no adapted _*.csv).
rm -rf "$WORK"; mkdir -p "$WORK/store/run1/in" "$WORK/store/empty"
for f in avft avgspeeddistribution dayvmtfraction fuelformulation fuelsupply fuelusagefraction \
         hourvmtfraction imcoverage monthvmtfraction roadtypedistribution sourcetypeagedistribution \
         sourcetypeyear sourcetypeyearvmt zonemonthhour; do cp "$FIXTURE/$f.csv" "$WORK/store/run1/in/"; done
cp "$FIXTURE/rs_custom.xml" "$FIXTURE/parameters.json" "$WORK/store/run1/in/"
STORE="$(cd "$WORK/store" && pwd -W 2>/dev/null || pwd)"

sync_run() {  # sync_run <log name> [docker run args...]; sets RC
  local log=$1; shift
  docker run --rm --cpus 2 -e MOVES_IO=sync -e MOVES_RETRY_SCALE=0 -e RCLONE_CONFIG_STORE_TYPE=local \
    -e "MOVES_IMAGE=$IMAGE" -e RUN_ID=d36109-u1-o1 "$@" \
    --mount "type=bind,src=$STORE,target=/store" --mount "type=bind,src=$SCRIPTS,target=/cat/scripts" \
    --entrypoint bash "$IMAGE" -c "./scripts/launch.sh" > "$WORK/$log" 2>&1
  RC=$?
}

echo "=== config error: MOVES_SYNC_REMOTE unset ==="
sync_run noremote
check "no remote: exit code is 5 (got $RC)" '[ "$RC" = 5 ]'

echo "=== fetch failure: the remote has no in/ folder ==="
sync_run nofetch -e MOVES_SYNC_REMOTE=store:/store/empty
check "no in/: exit code is 2 (got $RC)" '[ "$RC" = 2 ]'
check "no in/: nothing pushed to out/" '[ ! -e "$WORK/store/empty/out" ]'

echo "=== happy path: full Tompkins run in sync mode ==="
sync_run ok -e MOVES_SYNC_REMOTE=store:/store/run1
OUT="$WORK/store/run1/out"
check "ok: container exit code is 0 (got $RC)" '[ "$RC" = 0 ]'
for n in data.csv.gz moveslog.txt.gz replication.tar.xz run_manifest.json; do
  check "ok: $n landed in out/" '[ -s "$OUT/$n" ]'
done
check "ok: nothing else in out/ (got: $(ls "$OUT" 2>/dev/null | tr "\n" " "))" '[ "$(ls "$OUT" | wc -l)" = 4 ]'
check "ok: manifest status is ok" 'grep -q "\"status\": \"ok\"" "$OUT/run_manifest.json"'
mf() { python3 -I "$TESTS_DIR/manifest_get.py" "$OUT/run_manifest.json" "$1" 2>/dev/null; }
check "ok: manifest sha256 of data.csv.gz matches the pushed file" '[ "$(mf output:data.csv.gz)" = "$(sha256sum "$OUT/data.csv.gz" | cut -d" " -f1)" ]'
mkdir -p "$WORK/cmp" && gzip -dc "$OUT/data.csv.gz" > "$WORK/cmp/data.csv"
check "ok: data.csv equals the fixture reference (compare_outputs.py)" 'python3 -I "$REPO/moves_anywhere/scripts/compare_outputs.py" "$FIXTURE" "$WORK/cmp" --files data.csv > "$WORK/compare.txt" 2>&1'
check "ok: no rclone ERROR or CRITICAL line in the container log" '! grep -qE " (ERROR|CRITICAL) : " "$WORK/ok"'

echo
if [ "$FAILS" = 0 ]; then echo "PASS: all assertions"; else echo "FAIL: $FAILS assertion(s)"; fi
exit "$FAILS"
