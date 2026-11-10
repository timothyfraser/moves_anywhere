#!/bin/bash
# launch.sh ###################################################################
#
# What:      A script to run MOVES ANYWHERE at launch.
# Does:      Checks MOVES_IO, then runs every step of a run in order (steps 1 to 16 below):
#            fetch inputs (ticket/sync), check and adapt inputs, build and import the custom
#            database, run MOVES, postprocess, compress, pack, push (ticket/sync).
# Called by: the image's default command (Dockerfile: CMD [ "/cat/scripts/launch.sh" ])
# Reads:     MOVES_IO (mounted | ticket | sync), TICKET_URL, MOVES_PACK, /cat/inputs
# Writes:    /cat/inputs/.timings, /cat/run/stop_reason; each step writes its own outputs
# Exits:     0 if the run finished; 5 if MOVES_IO is unknown or TICKET_URL is missing or not https;
#            1 if compressing fails, or (mounted mode) if run_manifest.json says failed;
#            the exit status of an R step (4, 6, 7, 8, 11, 13) that fails: the run stops there and
#            writes stop_reason "<step> failed (exit N)" unless the step already wrote one;
#            otherwise the exit code of task_fetch_inputs.sh or task_push_outputs.sh
#            In mounted mode a failed step exits non-zero and prints the reason to the log, and no manifest
#            is written; in ticket/sync mode the pushed failed manifest carries the reason.
###############################################################################

# I/O mode dispatcher (docs/RUN_TICKET.md): mounted (default) | ticket | sync
MOVES_IO=${MOVES_IO:-mounted}
case "$MOVES_IO" in
  mounted|sync) ;;
  ticket) case "$TICKET_URL" in
      https://*|http://127.0.0.1[:/]*|http://localhost[:/]*|http://\[::1\][:/]*) ;;
      *) echo "---TICKET_URL is missing or not https"; exit 5 ;; esac ;;
  *) echo "---Unknown MOVES_IO: $MOVES_IO"; exit 5 ;;
esac
set -o pipefail
export MOVES_IO
export STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p /cat/run && rm -f /cat/run/stop_reason
# Stage timings for the run manifest: "stage seconds" lines, read by task_pack.sh.
TIMINGS=/cat/inputs/.timings
mkdir -p /cat/inputs; rm -f "$TIMINGS"
LAST_TICK=$(date +%s)
tick() { local n; n=$(date +%s); mkdir -p /cat/inputs; echo "$1 $((n - LAST_TICK))" >> "$TIMINGS"; LAST_TICK=$n; }
PUSHED=0
# On any non-zero exit, still push a failed manifest (not for config/ticket errors: nowhere trusted to write).
on_exit() {
  rc=$?
  trap - EXIT
  if [ "$rc" -ne 0 ] && [ "$MOVES_IO" != mounted ] && [ "$PUSHED" = 0 ] && [ "$rc" -ne 3 ] && [ "$rc" -ne 5 ]; then
    PUSHED=1
    mkdir -p /cat/run; [ -f /cat/run/stop_reason ] || printf 'MOVES exited %s: see moveslog.txt.gz' "$rc" > /cat/run/stop_reason
    cd /cat && PUSH_STATUS=failed bash scripts/task_push_outputs.sh
  fi
  exit "$rc"
}
trap on_exit EXIT

# 1. Fetch inputs (ticket/sync) ####
# Ticket/sync mode: fetch the inputs first.
if [ "$MOVES_IO" != mounted ]; then
  bash "scripts/task_fetch_inputs.sh" || exit $?
  tick fetch
fi

# 2. Check inputs ####
# Check for contents of inputs folder
. "scripts/task_check_inputs.sh"

# 3. Copy runspec ####
# Copy the runspec into place
. "scripts/task_copy_runspec.sh"
tick check_inputs


# 4. Check R packages ####
# Check if all R packages are installed.
Rscript "scripts/task_check_packages.R" || { rc=$?; [ -f /cat/run/stop_reason ] || printf '%s failed (exit %s): see moveslog.txt.gz' "task_check_packages.R" "$rc" > /cat/run/stop_reason; exit "$rc"; }

# 5. Start MySQL ####
# Start up mysql
. "scripts/task_start_mysql.sh"

# 6. Adapt inputs ####
# Initiate the adapt protocol
Rscript "scripts/task_adapt.R" || { rc=$?; [ -f /cat/run/stop_reason ] || printf '%s failed (exit %s): see moveslog.txt.gz' "task_adapt.R" "$rc" > /cat/run/stop_reason; exit "$rc"; }
tick adapt

# 7. Create custom database ####
# Create custom database
Rscript "scripts/task_db_create.R" || { rc=$?; [ -f /cat/run/stop_reason ] || printf '%s failed (exit %s): see moveslog.txt.gz' "task_db_create.R" "$rc" > /cat/run/stop_reason; exit "$rc"; }

# 8. Create importer ####
# Create importer script
Rscript "scripts/task_create_importer.R" || { rc=$?; [ -f /cat/run/stop_reason ] || printf '%s failed (exit %s): see moveslog.txt.gz' "task_create_importer.R" "$rc" > /cat/run/stop_reason; exit "$rc"; }
tick db_create

# 9. Import tables ####
# Import tables into newly created database
. "scripts/task_importer.sh"
tick importer

# 10. Launch MOVES ####
# Launch MOVES
. "scripts/task_launch_moves.sh"
tick moves


# 11. Postprocess ####
# Postprocess MOVES output data in R
Rscript "scripts/task_postprocess.R" || { rc=$?; [ -f /cat/run/stop_reason ] || printf '%s failed (exit %s): see moveslog.txt.gz' "task_postprocess.R" "$rc" > /cat/run/stop_reason; exit "$rc"; }
tick postprocess

# 12. Copy MOVES logs ####
# Copy MOVES logs into inputs folder
. "scripts/task_copy_logs.sh"

# 13. Summarize ####
# Summarize results quickly for diagnostics
Rscript "scripts/task_summarize.R" || { rc=$?; [ -f /cat/run/stop_reason ] || printf '%s failed (exit %s): see moveslog.txt.gz' "task_summarize.R" "$rc" > /cat/run/stop_reason; exit "$rc"; }

# 14. Compress outputs ####
# Compress outputs (child process: it must never end this job), then pack, then push (ticket/sync).
cd /cat || exit 1
bash scripts/task_compress_outputs.sh || { echo "---compressing outputs failed"; exit 1; }
# 15. Pack: replication kit and run manifest ####
if [ "${MOVES_PACK:-1}" != 0 ] && [ -f scripts/task_pack.sh ]; then
  # task_pack.sh owns replication.tar.xz and run_manifest.json (docs/RUN_MANIFEST.md).
  RUN_STATUS=ok RUN_STOP_REASON="MOVES finished" RUN_STARTED_AT="$STARTED_AT"     RUN_FINISHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ) INPUTS_DIR=/cat/inputs     bash scripts/task_pack.sh || echo "---pack reported a problem (manifest still written)"
fi
# 16. Push outputs (ticket/sync) ####
if [ "$MOVES_IO" != mounted ]; then
  PUSHED=1
  PUSH_STATUS=ok bash scripts/task_push_outputs.sh || exit $?
fi

# Finishup
if [ "$MOVES_IO" = mounted ] && [ "${MOVES_PACK:-1}" != 0 ] && [ -f inputs/run_manifest.json ] &&    python3 -I -c 'import json,sys; sys.exit(json.load(open("inputs/run_manifest.json"))["status"] != "failed")'; then
  echo "---run failed: see inputs/run_manifest.json and inputs/moveslog.txt"
  exit 1
fi
exit 0 # Exit without error
