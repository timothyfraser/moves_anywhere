#!/bin/bash
# test_ticket_mode.sh #########################################################
#
# What:      Proves MOVES_IO=ticket end to end against a local stub ticket server.
# Does:      The stub runs in a container too; the MOVES container joins its network namespace,
#            so TICKET_URL is a loopback http URL (the only http the dispatcher accepts) and
#            Docker Desktop needs no host networking. No inputs folder is mounted: everything
#            arrives through the ticket.
# Called by: Developer tool: test of ticket mode (MOVES_IO=ticket in launch.sh). Not run by launch.sh.
# Reads:     fixture_dir (or FIXTURE), tests/ticket_stub_server.py, tests/manifest_get.py
# Writes:    moves_anywhere/tests/.work/; strips CR from scripts/*.sh in place
# Exits:     1 if not in a git repository; otherwise the number of failed assertions
# Usage: bash moves_anywhere/tests/test_ticket_mode.sh [fixture_dir]
# Needs Docker and the image (IMAGE, default tmf77/moves-anywhere:v3).
###############################################################################

export MSYS_NO_PATHCONV=1
REPO=$(git rev-parse --show-toplevel) || exit 1
cd "$REPO" || exit 1
IMAGE=${IMAGE:-tmf77/moves-anywhere:v3}
SCRIPTS="$(pwd -W 2>/dev/null || pwd)/moves_anywhere/scripts"
TESTS="$(pwd -W 2>/dev/null || pwd)/moves_anywhere/tests"
FIXTURE=${1:-${FIXTURE:-C:/Users/tmf77/cloud_moves/moves_anywhere/moves_anywhere/inputs_ny}}
WORK="$REPO/moves_anywhere/tests/.work"
FAILS=0
TESTS_DIR="$REPO/moves_anywhere/tests"
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILS=$((FAILS + 1)); fi; }

for f in "$REPO"/moves_anywhere/scripts/*.sh; do sed -i 's/\r$//' "$f"; done

# User inputs only: 14 tables + runspec + parameters (no outputs, no adapted _*.csv).
make_case() {  # make_case <name>
  rm -rf "$WORK/$1"; mkdir -p "$WORK/$1/in" "$WORK/$1/out"
  for f in avft avgspeeddistribution dayvmtfraction fuelformulation fuelsupply fuelusagefraction \
           hourvmtfraction imcoverage monthvmtfraction roadtypedistribution sourcetypeagedistribution \
           sourcetypeyear sourcetypeyearvmt zonemonthhour; do cp "$FIXTURE/$f.csv" "$WORK/$1/in/"; done
  cp "$FIXTURE/rs_custom.xml" "$FIXTURE/parameters.json" "$WORK/$1/in/"
}

run_case() {  # run_case <name> [stub args...]; sets RC
  local n=$1; shift
  local w; w="$(cd "$WORK/$n" && pwd -W)"
  docker rm -f "ma_stub_$n" >/dev/null 2>&1
  docker run -d --rm --name "ma_stub_$n" --mount "type=bind,src=$TESTS,target=/t,readonly" \
    --mount "type=bind,src=$w,target=/w" --entrypoint python3 "$IMAGE" -I /t/ticket_stub_server.py \
    --in /w/in --out /w/out --log /w/puts.log --port 8765 "$@" >/dev/null
  sleep 2
  docker run --rm --cpus 2 --network "container:ma_stub_$n" \
    -e MOVES_IO=ticket -e "MOVES_IMAGE=$IMAGE" -e RUN_ID=d36109-u1-o1 -e MOVES_RETRY_SCALE=0 \
    -e "TICKET_URL=http://127.0.0.1:8765/ticket?t=SECRETTOKEN" \
    --mount "type=bind,src=$SCRIPTS,target=/cat/scripts" \
    --entrypoint bash "$IMAGE" -c "./scripts/launch.sh" > "$WORK/$n/container.log" 2>&1
  RC=$?
  docker rm -f "ma_stub_$n" >/dev/null 2>&1
}

echo "=== failure case: rs_custom.xml listed but 404 ==="
make_case fail; rm -f "$WORK/fail/in/rs_custom.xml"
run_case fail --ghost rs_custom.xml
OUT="$WORK/fail/out"
check "failure: container exit code is 2 (got $RC)" '[ "$RC" = 2 ]'
check "failure: run_manifest.json pushed with status failed" 'grep -q "\"status\": \"failed\"" "$OUT/run_manifest.json"'
check "failure: stop_reason names the file" 'grep -q "input fetch failed: rs_custom.xml HTTP 404" "$OUT/run_manifest.json"'
check "failure: MOVES never started (no data.csv.gz pushed)" '[ ! -e "$OUT/data.csv.gz" ]'

echo "=== happy path: full Tompkins run in ticket mode ==="
make_case ok
run_case ok
OUT="$WORK/ok/out"
check "ok: container exit code is 0 (got $RC)" '[ "$RC" = 0 ]'
for n in data.csv.gz moveslog.txt.gz replication.tar.xz run_manifest.json; do
  check "ok: $n landed in out/" '[ -s "$OUT/$n" ]'
done
check "ok: run_manifest.json was the LAST PUT" '[ "$(tail -n1 "$WORK/ok/puts.log")" = run_manifest.json ]'
check "ok: manifest status is ok" 'grep -q "\"status\": \"ok\"" "$OUT/run_manifest.json"'
want=$(wc -l < "$FIXTURE/data.csv"); got=$(gzip -dc "$OUT/data.csv.gz" | wc -l)
check "ok: data.csv.gz has $want lines (got $got)" '[ "$want" = "$got" ]'
check "ok: replication.tar.xz is a valid xz tar" 'tar --force-local -tJf "$OUT/replication.tar.xz" >/dev/null'
mf() { python3 -I "$TESTS_DIR/manifest_get.py" "$OUT/run_manifest.json" "$1" 2>/dev/null; }
want_sha=$(sha256sum "$OUT/data.csv.gz" | cut -d' ' -f1)
check "ok: manifest moves.commit is set (got $(mf moves.commit))" '[ -n "$(mf moves.commit)" ] && [ "$(mf moves.commit)" != None ]'
check "ok: manifest has image.name" '[ -n "$(mf image.name)" ]'
check "ok: manifest sha256 of data.csv.gz matches the pushed file" '[ "$(mf output:data.csv.gz)" = "$want_sha" ]'
check "ok: manifest lists replication.tar.xz (pack wrote it)" '[ -n "$(mf output:replication.tar.xz)" ]'
check "ok: no query string or token in container stdout" '! grep -qE "SECRETTOKEN|sig=stub|\?t=" "$WORK/ok/container.log"'

echo
if [ "$FAILS" = 0 ]; then echo "PASS: all assertions"; else echo "FAIL: $FAILS assertion(s)"; fi
exit "$FAILS"
