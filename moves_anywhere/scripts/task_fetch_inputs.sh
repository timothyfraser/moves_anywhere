#!/bin/bash

# task_fetch_inputs.sh

# Ticket mode: download this run's inputs into /cat/inputs (docs/RUN_TICKET.md section 3).
# Exit 2 = input fetch failed, 3 = ticket unusable, 5 = configuration error.
# Never prints a URL's query string.

echo ------------fetching inputs------------

RUNDIR=/cat/run
IN=/cat/inputs
mkdir -p "$RUNDIR" "$IN" && chmod 700 "$RUNDIR"
T="$RUNDIR/ticket.json"
SLEEP_SCALE=${MOVES_RETRY_SCALE:-1}   # tests set 0 to skip backoff

clean() { echo "${1%%\?*}"; }                       # scheme://host/path only
reason() { printf '%s' "$1" | head -c 110 > "$RUNDIR/stop_reason"; }

if [ "$MOVES_IO" = "sync" ]; then
  [ -n "$MOVES_SYNC_REMOTE" ] || { echo "---MOVES_SYNC_REMOTE is not set"; exit 5; }
  for i in 1 2 3; do
    rclone --config /dev/null copy "$MOVES_SYNC_REMOTE/in" "$IN" && exit 0
    sleep $((2 * i * SLEEP_SCALE))
  done
  reason "input fetch failed: sync copy"; exit 2
fi

# GET the ticket: 3 tries. Prints the HTTP status via return code (0 ok, 1 fail).
get_ticket() {
  local i code
  for i in 1 2 3; do
    code=$(curl -sS --retry 0 -o "$T.new" -w '%{http_code}' "$TICKET_URL" 2>/dev/null)
    if [ "$code" = "200" ]; then mv -f "$T.new" "$T"; chmod 600 "$T"; return 0; fi
    case "$code" in 401|403|404|410) break ;; esac
    sleep $((2 ** i * SLEEP_SCALE))
  done
  echo "---ticket fetch failed: HTTP ${code:-000} from $(clean "$TICKET_URL")"
  return 1
}

get_ticket || exit 3

# Validate the ticket; print one tab-separated line per input.
python3 -I -c '
import json, re, sys, os
t = json.load(open(sys.argv[1]))
pat = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$")
assert t.get("ticket_version") == 1, "ticket_version"
rid = os.environ.get("RUN_ID")
assert re.match(r"^d[0-9]{2,5}-u[0-9]+-o[0-9]+$", t.get("run_id", "")), "run_id"
assert not rid or rid == t["run_id"], "run_id mismatch"
names = [i["name"] for i in t["inputs"]]
assert all(pat.match(n) for n in names), "input name"
assert "rs_custom.xml" in names and "parameters.json" in names, "required inputs missing"
assert isinstance(t.get("outputs"), list) and t["outputs"], "outputs"
' "$T" 2>"$RUNDIR/ticket.err" || { echo "---ticket unusable: $(tail -1 "$RUNDIR/ticket.err")"; exit 3; }

[ -n "$RUN_ID" ] || RUN_ID=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["run_id"])' "$T")
echo "---ticket ok for run $RUN_ID"

list_inputs() {
  python3 -I -c '
import json, sys
for i in json.load(open(sys.argv[1]))["inputs"]:
    print(i["name"], i["url"], i.get("sha256", ""), i.get("bytes", ""), sep="\t")' "$T"
}

fail() {  # fail <name> <http>
  reason "input fetch failed: $1 HTTP $2"
  echo "---input fetch failed: $1 HTTP $2"
  exit 2
}

while IFS=$'\t' read -r name url sha bytes; do
  refetched=0; ok=0; code=000
  for i in 1 2 3; do
    code=$(curl -sS --retry 0 -o "$IN/$name.part" -w '%{http_code}' "$url" 2>/dev/null)
    if [[ "$code" =~ ^2 ]]; then
      got_ok=1
      [ -z "$bytes" ] || [ "$(stat -c %s "$IN/$name.part")" = "$bytes" ] || got_ok=0
      if [ -n "$sha" ] && [ "$got_ok" = 1 ]; then
        [ "$(sha256sum "$IN/$name.part" | cut -d' ' -f1)" = "$sha" ] || got_ok=0
      fi
      if [ "$got_ok" = 1 ]; then ok=1; break; fi
      code="checksum"
    elif [[ "$code" =~ ^(400|401|403|404)$ ]]; then
      # the link may have expired: take fresh links once, then stop
      if [ "$refetched" = 0 ] && get_ticket; then
        refetched=1
        url=$(list_inputs | awk -F'\t' -v n="$name" '$1==n {print $2}')
        continue
      fi
      break
    fi
    sleep $((2 ** i * SLEEP_SCALE))
  done
  [ "$ok" = 1 ] || { rm -f "$IN/$name.part"; fail "$name" "$code"; }
  mv -f "$IN/$name.part" "$IN/$name"
  echo "---fetched $name"
done < <(list_inputs)

exit 0
