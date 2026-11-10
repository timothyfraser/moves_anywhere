#!/bin/bash
# run_gate.sh #################################################################
#
# What:      The gate: builds the image from a commit and runs every check, one after another.
# Does:      Runs 10 steps (static, compare-unit, build, fixture, compare, manifest, pack, ticket,
#            bad-table, sha), never two containers at once, keeps going after a failure, and prints one
#            summary line per step. The image is built from a clean `git archive HEAD` export, so it gets
#            the committed LF scripts and the working tree is never touched.
# Called by: Developer tool: the release gate. Not run by launch.sh.
# Reads:     moves_anywhere/ (committed), moves_anywhere/inputs_ny (inputs and gold outputs), Docker
# Writes:    moves_anywhere/tests/.work/gate/ (one log per step); temp folders, removed on exit unless --keep
# Exits:     the number of failed steps (0 = gate passed); 2 on a usage error or if not run from the repo root
# Usage: bash moves_anywhere/tests/run_gate.sh [--image <name:tag>] [--skip-build] [--only <step>]
#                                              [--allow-dirty] [--keep]
# Run from the repository root. Default image: moves-anywhere:gate-<short git sha>.
###############################################################################

set -uo pipefail

MOVES_COMMIT=2c4cd1ab31b53bc9731492544fcbd0a6e47b970a
STEPS="static compare-unit build fixture compare manifest pack ticket bad-table sha"
IMAGE=""; SKIP_BUILD=0; ONLY=""; ALLOW_DIRTY=0; KEEP=0

usage() { sed -n "16,19p" "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --image) [ $# -ge 2 ] || { usage >&2; exit 2; }; IMAGE="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --only) [ $# -ge 2 ] || { usage >&2; exit 2; }; ONLY="$2"; shift 2 ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    --keep) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "run_gate.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [ -n "$ONLY" ]; then
  case " $STEPS " in *" $ONLY "*) ;; *) echo "run_gate.sh: unknown step $ONLY (steps: $STEPS)" >&2; exit 2 ;; esac
fi

# 1. Where we are ####
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "run_gate.sh: not in a git repository" >&2; exit 2; }
# An empty --show-prefix means the current folder is the top of the work tree. (Comparing two pwd strings
# fails on Git Bash, where the same folder can be spelled /c/..., C:/... or /tmp/....)
if [ ! -d moves_anywhere/tests ] || [ -n "$(git rev-parse --show-prefix)" ]; then
  echo "run_gate.sh: run it from the repository root ($TOP)" >&2; exit 2
fi
SHORT=$(git rev-parse --short HEAD)
[ -n "$IMAGE" ] || IMAGE="moves-anywhere:gate-$SHORT"
export MSYS_NO_PATHCONV=1   # as run.sh does: Git Bash must not rewrite container paths
export IMAGE

GATE_WORK="$TOP/moves_anywhere/tests/.work/gate"
rm -rf "$GATE_WORK"; mkdir -p "$GATE_WORK"
TMP=$(mktemp -d)
RUN_DIR="$TMP/run"        # the copy of the inputs that run.sh runs in
EXPORT_DIR="$TMP/export"  # the git archive export the image is built from
GOLD="$TOP/moves_anywhere/inputs_ny"
cleanup() { [ "$KEEP" = 1 ] && echo "kept: $TMP and $GATE_WORK" || rm -rf "$TMP"; }
trap cleanup EXIT

# 2. Step bookkeeping ####
RESULTS=(); FAILED=0
# record <status> <name> <seconds>
record() { RESULTS+=("$(printf '%-5s %-13s %ss' "$1" "$2" "$3")"); [ "$1" = FAIL ] && FAILED=$((FAILED + 1)); return 0; }
# run_step <n> <name> <function>: runs the function with its output in the step log and on screen
run_step() {
  local n=$1 name=$2 fn=$3 t0 rc
  echo "=== $n. $name"
  if [ -n "$ONLY" ] && [ "$ONLY" != "$name" ]; then record SKIP "$name" 0; echo "(skipped)"; return; fi
  t0=$SECONDS
  "$fn" 2>&1 | tee "$GATE_WORK/$n-$name.log"
  rc=${PIPESTATUS[0]}
  if [ "$rc" = 99 ]; then record SKIP "$name" $((SECONDS - t0))
  elif [ "$rc" = 0 ]; then record PASS "$name" $((SECONDS - t0))
  else record FAIL "$name" $((SECONDS - t0)); fi
}

# 3. The steps ####
step_static() { bash moves_anywhere/tests/test_dockerfile_static.sh; }

step_compare_unit() { python -I moves_anywhere/scripts/test_compare_outputs.py; }

step_build() {
  if [ "$SKIP_BUILD" = 1 ]; then
    docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "--skip-build but image $IMAGE does not exist"; return 1; }
    echo "skipping build; using existing $IMAGE"; return 99
  fi
  if [ "$ALLOW_DIRTY" = 0 ] && [ -n "$(git status --porcelain -- moves_anywhere)" ]; then
    echo "moves_anywhere has uncommitted changes; the gate tests exactly a commit (use --allow-dirty to override):"
    git status --porcelain -- moves_anywhere; return 1
  fi
  mkdir -p "$EXPORT_DIR" && git archive HEAD moves_anywhere | tar -x -C "$EXPORT_DIR" || { echo "git archive failed"; return 1; }
  local ctx="$EXPORT_DIR/moves_anywhere"
  command -v cygpath >/dev/null 2>&1 && ctx=$(cygpath -m "$ctx")
  docker build --build-arg "MOVES_COMMIT=$MOVES_COMMIT" -t "$IMAGE" "$ctx" || return 1
  echo "image id: $(docker image inspect --format '{{.Id}}' "$IMAGE")"
}

step_fixture() {
  # The user inputs only: 14 tables + runspec + parameters (what the bad-table test copies).
  rm -rf "$RUN_DIR"; mkdir -p "$RUN_DIR"
  local f
  for f in avft avgspeeddistribution dayvmtfraction fuelformulation fuelsupply fuelusagefraction \
           hourvmtfraction imcoverage monthvmtfraction roadtypedistribution sourcetypeagedistribution \
           sourcetypeyear sourcetypeyearvmt zonemonthhour; do
    cp "$GOLD/$f.csv" "$RUN_DIR/" || { echo "missing input $f.csv"; return 1; }
  done
  cp "$GOLD/rs_custom.xml" "$GOLD/parameters.json" "$RUN_DIR/" || return 1
  bash moves_anywhere/run.sh "$RUN_DIR" --image "$IMAGE"
}

# rows <name>: data rows of a run output, plain or .gz
rows() {
  local n
  if [ -f "$RUN_DIR/$1" ]; then n=$(wc -l < "$RUN_DIR/$1")
  elif [ -f "$RUN_DIR/$1.gz" ]; then n=$(gzip -dc "$RUN_DIR/$1.gz" | wc -l)
  else echo -1; return; fi
  echo $((n - 1))
}

step_compare() {
  [ -d "$RUN_DIR" ] || { echo "no run folder (fixture step did not run)"; return 1; }
  local cmp="$RUN_DIR" out rc=0 f
  # compare_outputs.py reads plain .csv only: expand .gz if that is all the run left.
  for f in movesoutput.csv movesactivityoutput.csv data.csv; do
    if [ ! -f "$RUN_DIR/$f" ] && [ -f "$RUN_DIR/$f.gz" ]; then
      [ "$cmp" = "$RUN_DIR" ] && { cmp="$TMP/run_plain"; mkdir -p "$cmp"; }
      gzip -dc "$RUN_DIR/$f.gz" > "$cmp/$f"
    fi
  done
  out=$(python -I moves_anywhere/scripts/compare_outputs.py "$GOLD" "$cmp"); rc=$?
  printf '%s\n' "$out"
  [ "$rc" = 0 ] || { echo "compare_outputs.py exited $rc"; return 1; }
  printf '%s\n' "$out" | grep -q 'OVERALL: PASS' || { echo "no OVERALL: PASS in the output"; return 1; }
  local a b bad=0
  a=$(rows movesoutput.csv); b=$(rows movesactivityoutput.csv)
  echo "movesoutput.csv data rows: $a (expect 7588)"
  echo "movesactivityoutput.csv data rows: $b (expect 870)"
  [ "$a" = 7588 ] || bad=1
  [ "$b" = 870 ] || bad=1
  return "$bad"
}

step_manifest() {
  local s
  s=$(python3 -I moves_anywhere/tests/manifest_get.py "$RUN_DIR/run_manifest.json" status | tr -d '\r') || return 1
  echo "run_manifest.json status: $s"
  [ "$s" = ok ]
}

step_pack() { bash moves_anywhere/tests/test_pack.sh "$RUN_DIR"; }

step_ticket() { IMAGE="$IMAGE" FIXTURE="$GOLD" bash moves_anywhere/tests/test_ticket_mode.sh; }

step_bad_table() { IMAGE="$IMAGE" bash moves_anywhere/tests/test_bad_table.sh; }

step_sha() {
  local run gold
  gold=$(sha256sum "$GOLD/data.csv" | cut -d' ' -f1) || return 1
  if [ -f "$RUN_DIR/data.csv" ]; then run=$(sha256sum "$RUN_DIR/data.csv" | cut -d' ' -f1)
  elif [ -f "$RUN_DIR/data.csv.gz" ]; then run=$(gzip -dc "$RUN_DIR/data.csv.gz" | sha256sum | cut -d' ' -f1)
  else echo "run data.csv is missing"; return 1; fi
  echo "run  data.csv sha256: $run"
  echo "gold data.csv sha256: $gold"
  [ "$run" = "$gold" ] && echo "identical" || echo "different (informational only: compare step decides exactness)"
  return 0
}

# 4. Run them, strictly in order ####
T_ALL=$SECONDS
run_step 1  static       step_static
run_step 2  compare-unit step_compare_unit
run_step 3  build        step_build
run_step 4  fixture      step_fixture
run_step 5  compare      step_compare
run_step 6  manifest     step_manifest
run_step 7  pack         step_pack
run_step 8  ticket       step_ticket
run_step 9  bad-table    step_bad_table
run_step 10 sha          step_sha

# 5. Summary ####
echo
echo "=== summary"
for r in "${RESULTS[@]}"; do echo "$r"; done
ID=$(docker image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null || echo unknown)
echo "IMAGE $IMAGE $ID"
echo "total ${SECONDS}s (steps: $((SECONDS - T_ALL))s)"
if [ "$FAILED" = 0 ]; then echo "GATE: PASS"; else echo "GATE: FAIL ($FAILED steps)"; fi
exit "$FAILED"
