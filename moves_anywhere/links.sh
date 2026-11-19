#!/usr/bin/env bash
# links.sh: build the link table of a project-scale run from public road data, with Docker.
#
#   bash links.sh <folder> --place "<west,south,east,north>" | --place <5-digit FIPS> --state <two letters>
#                 [--max-links N] [--no-fill] [--overwrite] [--image IMAGE]
#
# The folder needs rs_custom.xml (a project run file). The links land in the same folder: link.csv,
# link_summary.txt and the other link files. Check them, then run MOVES with run.sh. Default: at most 40 links.
#
# What:      Command-line wrapper that builds link.csv for one project-scale run in the Docker image.
# Does:      Checks the arguments and Docker, then runs `docker run --rm` with the folder mounted at /cat/inputs and scripts/launch_links.sh as the command.
# Called by: A person at a terminal, before run.sh.
# Reads:     <folder>/rs_custom.xml; environment: MOVES_IMAGE
# Writes:    Nothing itself. The container writes link.csv, link_summary.txt and the other link files into <folder>.
# Needs:     bash, Docker (running); cygpath when present (Git Bash on Windows)
# Exits:     0 if the links were written; 2 on a usage error or missing inputs; 3 if Docker is missing or not running; otherwise the container's exit status
set -u

IMAGE="${MOVES_IMAGE:-tmf77/moves-anywhere:v3}"
INPUTS=""
PLACE=""
STATE=""
MAX_LINKS=40
FILL=true
OVERWRITE=0

usage() { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "links.sh: $1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --place) [ $# -ge 2 ] || { usage >&2; exit 2; }; PLACE="$2"; shift 2 ;;
    --state) [ $# -ge 2 ] || { usage >&2; exit 2; }; STATE="$2"; shift 2 ;;
    --max-links) [ $# -ge 2 ] || { usage >&2; exit 2; }; MAX_LINKS="$2"; shift 2 ;;
    --no-fill) FILL=false; shift ;;
    --overwrite) OVERWRITE=1; shift ;;
    --image) [ $# -ge 2 ] || { usage >&2; exit 2; }; IMAGE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "links.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) [ -z "$INPUTS" ] || die "only one inputs folder"; INPUTS="$1"; shift ;;
  esac
done

[ -n "$INPUTS" ] || { usage >&2; exit 2; }
[ -d "$INPUTS" ] || die "no such folder: $INPUTS"
[ -f "$INPUTS/rs_custom.xml" ] || die "$INPUTS has no rs_custom.xml"
[ -n "$PLACE" ] || die "--place is required (a box \"west,south,east,north\" or a 5-digit county FIPS)"
[ -n "$STATE" ] || die "--state is required (two letters, for example NY)"

case "$MAX_LINKS" in ''|*[!0-9]*) die "--max-links must be a whole number"; esac
STATE="$(printf '%s' "$STATE" | tr '[:lower:]' '[:upper:]')"
case "$STATE" in [A-Z][A-Z]) ;; *) die "--state must be two letters, got: $STATE" ;; esac

case "$PLACE" in
  *,*)
    # A box: four numbers, west < east, south < north, within -180..180 and -90..90.
    printf '%s' "$PLACE" | awk -F, '
      function num(s) { return s ~ /^[ ]*-?[0-9]+(\.[0-9]+)?[ ]*$/ || s ~ /^[ ]*-?\.[0-9]+[ ]*$/ }
      NF != 4 { exit 1 }
      { for (i = 1; i <= 4; i++) if (!num($i)) exit 1
        w = $1 + 0; s = $2 + 0; e = $3 + 0; n = $4 + 0
        if (w < -180 || e > 180 || s < -90 || n > 90 || w < -180 || e < -180 || w > 180 || s > 90 || n < -90 || e > 180) exit 1
        if (!(w < e && s < n)) exit 1 }' \
      || die "--place box must be four numbers west,south,east,north with west < east and south < north, within -180..180 and -90..90"
    PLACE="$(printf '%s' "$PLACE" | tr -d ' ')"
    ;;
  *)
    case "$PLACE" in
      [0-9][0-9][0-9][0-9][0-9]) ;;
      *) die "--place must be a box \"west,south,east,north\" or a 5-digit county FIPS, got: $PLACE" ;;
    esac
    ;;
esac

command -v docker >/dev/null 2>&1 || { echo "links.sh: Docker is not installed or not on PATH" >&2; exit 3; }
docker info >/dev/null 2>&1 || { echo "links.sh: Docker is not running" >&2; exit 3; }

# Docker on Windows needs a Windows path, and Git Bash must not rewrite the /cat/inputs side.
ABS="$(cd "$INPUTS" && pwd)"
command -v cygpath >/dev/null 2>&1 && ABS="$(cygpath -m "$ABS")"
export MSYS_NO_PATHCONV=1

NAME="links-$$"
trap 'docker rm -f "$NAME" >/dev/null 2>&1' INT TERM
export PLACE STATE MAX_LINKS OVERWRITE
export MA_FILL_REMAINDER="$FILL"
echo "links.sh: $IMAGE on $ABS (place $PLACE, state $STATE, at most $MAX_LINKS links)"
docker run --rm --name "$NAME" -e PLACE -e STATE -e MAX_LINKS -e MA_FILL_REMAINDER -e OVERWRITE -v "$ABS:/cat/inputs" "$IMAGE" /cat/scripts/launch_links.sh
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "links.sh: wrote link.csv and link_summary.txt in $INPUTS; check them, then: bash run.sh $INPUTS"
else
  echo "links.sh: failed with exit $rc." >&2
  if [ -s "$INPUTS/link_summary.txt" ]; then tail -n 1 "$INPUTS/link_summary.txt" >&2; fi
fi
exit "$rc"
