#!/usr/bin/env bash
# run.sh: run MOVES on one folder of inputs with Docker, on Linux, macOS or Windows Git Bash.
#
#   bash run.sh <inputs-folder> [--image IMAGE] [--cpus N] [--memory SIZE]
#
# The folder needs rs_custom.xml, plus any custom input tables as <table>.csv. Results land in the same
# folder: data.csv, moveslog.txt, run_manifest.json. The exit status is 0 only when the run produced
# results. Defaults: 2 CPUs, 6 GB, the released image. MOVES uses about one core at a time.
#
# What:      Command-line wrapper that runs one MOVES run in the Docker image.
# Does:      Checks the inputs folder and Docker, then runs `docker run --rm` with the folder mounted at /cat/inputs.
# Called by: A person at a terminal. run.ps1 is the PowerShell equivalent.
# Reads:     <inputs-folder>/rs_custom.xml and any custom tables; environment: MOVES_IMAGE
# Writes:    Nothing itself. The container writes data.csv, moveslog.txt and run_manifest.json into <inputs-folder>.
# Needs:     bash, Docker (running); cygpath when present (Git Bash on Windows)
# Exits:     0 if the run produced results; 2 on a usage error or missing inputs; 3 if Docker is missing or not running; otherwise the container's exit status
set -u

IMAGE="${MOVES_IMAGE:-tmf77/moves-anywhere:v3}"
CPUS=2
MEMORY=6g
INPUTS=""

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --image) [ $# -ge 2 ] || { usage >&2; exit 2; }; IMAGE="$2"; shift 2 ;;
    --cpus) [ $# -ge 2 ] || { usage >&2; exit 2; }; CPUS="$2"; shift 2 ;;
    --memory) [ $# -ge 2 ] || { usage >&2; exit 2; }; MEMORY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "run.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) [ -z "$INPUTS" ] || { echo "run.sh: only one inputs folder" >&2; exit 2; }; INPUTS="$1"; shift ;;
  esac
done

[ -n "$INPUTS" ] || { usage >&2; exit 2; }
[ -d "$INPUTS" ] || { echo "run.sh: no such folder: $INPUTS" >&2; exit 2; }
[ -f "$INPUTS/rs_custom.xml" ] || { echo "run.sh: $INPUTS has no rs_custom.xml" >&2; exit 2; }
command -v docker >/dev/null 2>&1 || { echo "run.sh: Docker is not installed or not on PATH" >&2; exit 3; }
docker info >/dev/null 2>&1 || { echo "run.sh: Docker is not running" >&2; exit 3; }

# Docker on Windows needs a Windows path, and Git Bash must not rewrite the /cat/inputs side.
ABS="$(cd "$INPUTS" && pwd)"
command -v cygpath >/dev/null 2>&1 && ABS="$(cygpath -m "$ABS")"
export MSYS_NO_PATHCONV=1

NAME="moves-run-$$"
trap 'docker rm -f "$NAME" >/dev/null 2>&1' INT TERM
echo "run.sh: $IMAGE on $ABS ($CPUS CPUs, $MEMORY)"
docker run --rm --name "$NAME" --cpus "$CPUS" -m "$MEMORY" -v "$ABS:/cat/inputs" "$IMAGE"
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "run.sh: finished. Results are in $INPUTS"
else
  echo "run.sh: failed with exit $rc. See moveslog.txt and run_manifest.json in $INPUTS" >&2
fi
exit "$rc"
