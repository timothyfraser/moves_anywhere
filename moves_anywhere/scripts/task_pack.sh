#!/bin/bash
# task_pack.sh
#
# Pack step: after the outputs are compressed, write
#   replication.tar.xz  a kit that reproduces the run on a stock MOVES install
#   run_manifest.json   the run's final record (docs/RUN_MANIFEST.md)
# into $INPUTS_DIR. Source it (". scripts/task_pack.sh") or run it; it is idempotent:
# a second run on the same folder produces a byte-identical replication.tar.xz.
#
# Environment (all optional): INPUTS_DIR (/cat/inputs), RUN_ID, MOVES_IMAGE,
# MOVES_IMAGE_DIGEST, MOVES_COMMIT, MOVES_DIR (/cat/EPA_MOVES_Model), MOVES_DEFAULT_DB
# (movesdb20241112), MOVES_DEBUG, RUN_STATUS (ok|failed), RUN_STOP_REASON, RUN_STARTED_AT,
# RUN_FINISHED_AT. Stage timings are read from $INPUTS_DIR/.timings ("stage seconds").
#
# Exit status: 0 = kit and valid manifest written; 1 = something was written but a check
# failed (the manifest is still written, so the run still ends with a manifest).

_tp_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

task_pack() (
  # Everything runs in a subshell: sourcing this file never leaks variables, cwd or options.
  set -u -o pipefail
  LC_ALL=C; export LC_ALL

  INPUTS_DIR="${INPUTS_DIR:-/cat/inputs}"
  MOVES_DIR="${MOVES_DIR:-/cat/EPA_MOVES_Model}"
  t0=$(date +%s)
  rc=0

  cd "$INPUTS_DIR" || { echo "task_pack: cannot enter $INPUTS_DIR" >&2; exit 1; }
  work="$(mktemp -d)"
  cleanup() { rm -rf "$work" "$INPUTS_DIR/kit" "$INPUTS_DIR/replication.tar.xz.part" "$INPUTS_DIR/run_manifest.json.part"; }
  trap cleanup EXIT

  # --- 1. Classify files -------------------------------------------------------------
  # Not user inputs: files the pipeline itself writes at the top of the folder.
  not_user() {
    case "$1" in
      data.csv|movesoutput.csv|movesactivityoutput.csv) return 0 ;;
      rateperhour.csv|ratepervehicle.csv|rateperdistance.csv|rateperstart.csv) return 0 ;;
      startspervehicle.csv|rateperprofile.csv|movesrun.csv) return 0 ;;
    esac
    return 1
  }
  user_csv=(); adapted_csv=()
  for f in *.csv; do
    [ -f "$f" ] || continue
    case "$f" in
      _*) adapted_csv+=("$f") ;;
      *)  not_user "$f" || user_csv+=("$f") ;;
    esac
  done

  # --- 2. Kit ------------------------------------------------------------------------
  mkdir -p kit
  if [ -f importer.xml ]; then
    # The generated importer has absolute /cat/inputs/ paths; the kit copy is relative.
    sed 's|/cat/inputs/|./|g' importer.xml > kit/importer.xml
    if grep -q '/cat/' kit/importer.xml; then
      echo "task_pack: warning: /cat/ path left in kit/importer.xml" >&2
    fi
  fi
  cat > kit/README.txt <<'EOF'
MOVES ANYWHERE replication kit. Step by step: docs/REPLICATION_KIT.md in the
moves_anywhere repository (https://github.com/timothyfraser/moves_anywhere).

What is here: rs_custom.xml (the runspec), parameters.json, the user tables,
the adapted tables (_*.csv, the exact MOVES input tables), movesoutput.csv and
movesactivityoutput.csv (the reference results), diagnostics.txt and
moveslog.txt when present, and kit/importer.xml.

Reproduce: on a stock MOVES 5 install create an empty MySQL database named
custom, import the _*.csv tables into it with kit/importer.xml, run
rs_custom.xml in MOVES, and compare your movesoutput table with the
movesoutput.csv here: per-key sums must be identical.

kit/importer.xml uses relative paths (./_name.csv). To point it at the folder
where you extracted this kit, run once from that folder:
  sed "s|<filename>\./|<filename>$(pwd)/|" kit/importer.xml > importer_abs.xml
EOF

  members=()
  for f in rs_custom.xml parameters.json movesoutput.csv movesactivityoutput.csv diagnostics.txt moveslog.txt; do
    [ -f "$f" ] && members+=("$f")
  done
  members+=("${user_csv[@]}" "${adapted_csv[@]}" kit/README.txt)
  [ -f kit/importer.xml ] && members+=(kit/importer.xml)
  printf '%s\n' "${members[@]}" | sort -u > "$work/members.txt"

  rm -f replication.tar.xz.part
  if tar -cf - --no-recursion --mtime=@0 --owner=0 --group=0 --numeric-owner \
         --mode='u=rw,go=r' -T "$work/members.txt" | xz -6 -T0 > replication.tar.xz.part; then
    mv -f replication.tar.xz.part replication.tar.xz
  else
    echo "task_pack: building replication.tar.xz failed" >&2
    rm -f replication.tar.xz.part replication.tar.xz
    rc=1
  fi
  rm -rf kit

  # --- 3. Checksums ------------------------------------------------------------------
  tsv_row() { # name -> "name<TAB>bytes<TAB>sha256"
    local h _x n
    read -r h _x < <(sha256sum -- "$1")
    n=$(wc -c < "$1" | tr -d '[:space:]')
    printf '%s\t%s\t%s\n' "$1" "$n" "$h"
  }
  : > "$work/inputs.tsv"; : > "$work/outputs.tsv"
  # Inputs: what the user supplied (runspec, parameters, user tables), not the adapted _*.csv.
  for f in rs_custom.xml parameters.json "${user_csv[@]}"; do
    [ -f "$f" ] && tsv_row "$f" >> "$work/inputs.tsv"
  done
  # Outputs: the objects the platform expects (docs/RUN_TICKET.md), those present.
  for f in data.csv.gz rateperhour.csv.gz ratepervehicle.csv.gz rateperdistance.csv.gz \
           rateperstart.csv.gz startspervehicle.csv.gz rateperprofile.csv.gz movesrun.csv.gz \
           moveslog.txt.gz replication.tar.xz; do
    [ -f "$f" ] && tsv_row "$f" >> "$work/outputs.tsv"
  done

  # --- 4. Manifest -------------------------------------------------------------------
  commit=""
  if [ -d "$MOVES_DIR/.git" ] && command -v git >/dev/null 2>&1; then
    commit="$(git -C "$MOVES_DIR" rev-parse --short HEAD 2>/dev/null || true)"
  fi
  [ -n "$commit" ] || commit="${MOVES_COMMIT:-}"
  debug=0; [ "${MOVES_DEBUG:-}" = "1" ] && debug=1

  schema=""
  for cand in "$_tp_here/../../docs/RUN_MANIFEST.md" "$_tp_here/../docs/RUN_MANIFEST.md"; do
    [ -f "$cand" ] && { schema="$cand"; break; }
  done

  [ -n "${RUN_FAILED_PACK:-}" ] && true
  status="${RUN_STATUS:-ok}"
  reason="${RUN_STOP_REASON:-}"
  if [ "$rc" -ne 0 ] && [ "$status" = "ok" ]; then
    status=failed; reason="replication kit could not be built"
  fi
  # MOVES can stop on a bad runspec and the pipeline still reach here. No results means a failed
  # run, whatever exit codes came before: ok must never describe a run with nothing in it.
  if [ "$status" = "ok" ]; then
    need=data.csv
    grep -qi 'modelscale value="Rates"' rs_custom.xml 2>/dev/null && need=rateperdistance.csv
    if [ ! -s "$need" ] && [ ! -s "$need.gz" ]; then
      status=failed; reason="MOVES produced no results: see moveslog"
    fi
  fi

  python3 -I "$_tp_here/manifest_fields.py" \
    --out run_manifest.json \
    --inputs-tsv "$work/inputs.tsv" --outputs-tsv "$work/outputs.tsv" \
    --timings "$INPUTS_DIR/.timings" --parameters parameters.json --runspec rs_custom.xml \
    --run-id "${RUN_ID:-}" --status "$status" --stop-reason "$reason" \
    --image-name "${MOVES_IMAGE:-}" --image-digest "${MOVES_IMAGE_DIGEST:-}" \
    --moves-commit "$commit" --default-db "${MOVES_DEFAULT_DB:-movesdb20241112}" \
    --debug "$debug" --started-at "${RUN_STARTED_AT:-}" --finished-at "${RUN_FINISHED_AT:-}" \
    --pack-seconds "$(( $(date +%s) - t0 ))" --schema-from "$schema" || rc=1

  echo "task_pack: replication.tar.xz $(wc -c < replication.tar.xz 2>/dev/null | tr -d '[:space:]') bytes, run_manifest.json written (rc=$rc)"
  exit "$rc"
)

task_pack; _tp_rc=$?
if (return 0 2>/dev/null); then return "$_tp_rc"; else exit "$_tp_rc"; fi
