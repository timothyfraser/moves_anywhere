#!/bin/bash

# launch.sh

# A script to run MOVES ANYWHERE at launch.

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

# Ticket/sync mode: fetch the inputs first.
if [ "$MOVES_IO" != mounted ]; then
  bash "scripts/task_fetch_inputs.sh" || exit $?
  tick fetch
fi

# Check for contents of inputs folder
. "scripts/task_check_inputs.sh"

# Check for contents of inputs folder
. "scripts/task_copy_runspec.sh"
tick check_inputs


# Check if all R packages are installed.
Rscript "scripts/task_check_packages.R"

# Start up mysql
. "scripts/task_start_mysql.sh"

# Initiate the adapt protocol
# Rscript "scripts/task_adapt.R"
Rscript "scripts/task_adapt.R"
tick adapt

# Create custom database
Rscript "scripts/task_db_create.R"

# Create importer script
Rscript "scripts/task_create_importer.R"
tick db_create

# Import tables into newly created database
. "scripts/task_importer.sh"
tick importer

# Copy MOVES logs into inputs bucket
. "scripts/task_launch_moves.sh"
tick moves


# Postprocess MOVES output data in R
Rscript "scripts/task_postprocess.R"
tick postprocess

# Copy MOVES logs into inputs bucket
. "scripts/task_copy_logs.sh"

# Summarize results quickly for diagnostics
Rscript "scripts/task_summarize.R"

# Compress outputs (child process: it must never end this job), then pack, then push (ticket/sync).
cd /cat || exit 1
bash scripts/task_compress_outputs.sh || { echo "---compressing outputs failed"; exit 1; }
if [ "${MOVES_PACK:-1}" != 0 ] && [ -f scripts/task_pack.sh ]; then
  # task_pack.sh owns replication.tar.xz and run_manifest.json (docs/RUN_MANIFEST.md).
  RUN_STATUS=ok RUN_STOP_REASON="MOVES finished" RUN_STARTED_AT="$STARTED_AT"     RUN_FINISHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ) INPUTS_DIR=/cat/inputs     bash scripts/task_pack.sh || echo "---pack reported a problem (manifest still written)"
fi
if [ "$MOVES_IO" != mounted ]; then
  PUSHED=1
  PUSH_STATUS=ok bash scripts/task_push_outputs.sh || exit $?
fi

# Finishup
exit 0 # Exit without error
