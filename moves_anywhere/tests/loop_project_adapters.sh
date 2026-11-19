#!/bin/bash
# loop_project_adapters.sh ####################################################
#
# What:      Repeats the adapt step of a project-scale run to catch the intermittent adapter failure (PS-21,
#            2026-11-19: "PROJECT LINK TABLES" failed once, after a connection was closed by the garbage collector).
# Does:      Starts ONE container (ps21-loop, --rm) from the image with inputs_project/ mounted read-only at /fixture.
#            Inside it: starts MySQL as launch.sh does, then N times: fresh copy of the four fixture inputs into
#            /cat/inputs, runspec copied into place (task_copy_runspec.sh), and scripts/task_adapt.R run with a
#            gc() forced at the start of every run_adapter() call, so a connection left open by an earlier adapter
#            is finalised between adapters rather than at a random moment. The county adapters run each loop too,
#            because the project adapters read the tables they write. Stops at the first failure and prints its
#            full log.
# Called by: by hand / the orchestrator. Not part of run_gate.sh.
# Reads:     moves_anywhere/inputs_project/ (rs_custom.xml, link.csv, driveschedulesecondlink.csv, offnetworklink.csv)
# Writes:    nothing on the host; the container is removed on exit
# Exits:     0 if every loop passed, 1 at the first failed loop, 2 on a usage error
# Prints:    one line per loop, then "LOOPS OK: n" or "LOOP FAILED at i"
# Usage:     bash moves_anywhere/tests/loop_project_adapters.sh <image:tag> <loops>
# Needs Docker and the image. One heavy container at a time on this machine.
###############################################################################

IMAGE=$1; N=$2
if [ -z "$IMAGE" ] || ! [[ "$N" =~ ^[1-9][0-9]*$ ]]; then
  echo "usage: bash moves_anywhere/tests/loop_project_adapters.sh <image:tag> <loops>" >&2; exit 2
fi
REPO=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "loop_project_adapters.sh: not in a git repository" >&2; exit 2; }
FIXTURE="$REPO/moves_anywhere/inputs_project"
[ -d "$FIXTURE" ] || { echo "loop_project_adapters.sh: no fixture at $FIXTURE" >&2; exit 2; }
# Docker on Windows needs a Windows path, and Git Bash must not rewrite the container side
command -v cygpath >/dev/null 2>&1 && FIXTURE="$(cygpath -m "$FIXTURE")"
export MSYS_NO_PATHCONV=1

docker run --rm --name ps21-loop -e LOOPS="$N" -v "$FIXTURE:/fixture:ro" --entrypoint bash "$IMAGE" -c '
cd /cat || exit 1
. scripts/task_start_mysql.sh > /tmp/mysql.log 2>&1
# task_adapt.R with gc() at the start of each adapter group
sed "s/^run_adapter = function(name, expr){$/&\n  invisible(gc())/" scripts/task_adapt.R > /tmp/task_adapt_gc.R
grep -q "^  invisible(gc())$" /tmp/task_adapt_gc.R || { echo "could not add gc() to run_adapter"; echo "LOOP FAILED at 0"; exit 1; }
i=1
while [ "$i" -le "$LOOPS" ]; do
  rm -rf /cat/inputs /cat/run; mkdir -p /cat/inputs /cat/run
  for f in rs_custom.xml link.csv driveschedulesecondlink.csv offnetworklink.csv; do cp "/fixture/$f" /cat/inputs/ || exit 1; done
  . scripts/task_copy_runspec.sh > /dev/null
  start=$(date +%s)
  if Rscript /tmp/task_adapt_gc.R > /tmp/loop.log 2>&1; then
    echo "loop $i: ok ($(( $(date +%s) - start )) s, $(grep -c "call dbDisconnect" /tmp/loop.log) gc-closed connection warnings)"
  else
    echo "loop $i: FAILED ($(cat /cat/run/stop_reason 2>/dev/null))"
    echo "----- full log of loop $i -----"; cat /tmp/loop.log; echo "----- end of log -----"
    echo "LOOP FAILED at $i"; exit 1
  fi
  i=$((i + 1))
done
echo "LOOPS OK: $LOOPS"
'
