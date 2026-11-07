#!/bin/bash
# task_push_outputs.sh ########################################################
#
# What:      Ticket/sync mode: store the outputs, then run_manifest.json LAST (docs/RUN_TICKET.md section 4).
# Does:      Never prints a URL's query string.
# Called by: launch.sh, step 16 of launch.sh (ticket/sync mode only), and by launch.sh's
#            exit trap with PUSH_STATUS=failed when a ticket/sync run ends non-zero.
# Reads:     Env in: PUSH_STATUS (ok|failed, default ok), PUSH_STOP_REASON (optional), STARTED_AT.
#            Also MOVES_IO, TICKET_URL, MOVES_SYNC_REMOTE, MOVES_RETRY_SCALE, /cat/run/ticket.json,
#            /cat/run/stop_reason, and the outputs in /cat/inputs.
# Writes:    the outputs and run_manifest.json to the ticket URLs (ticket) or MOVES_SYNC_REMOTE/out
#            (sync); /cat/run/stored.txt; may rewrite /cat/inputs/run_manifest.json.
# Exits:     Exit 4 = push failed. Exit 0 = everything stored and status ok.
#            5 if MOVES_SYNC_REMOTE is not set (sync); 1 if a required output is missing or the
#            status is not ok.
###############################################################################

echo ------------pushing outputs------------

RUNDIR=/cat/run
IN=/cat/inputs
T="$RUNDIR/ticket.json"
SLEEP_SCALE=${MOVES_RETRY_SCALE:-1}
STATUS=${PUSH_STATUS:-ok}
REASON=${PUSH_STOP_REASON:-}
[ -z "$REASON" ] && [ -f "$RUNDIR/stop_reason" ] && REASON=$(cat "$RUNDIR/stop_reason")
[ "$STATUS" = ok ] && REASON="MOVES finished"
[ -n "$REASON" ] || REASON="MOVES failed"
STORED="$RUNDIR/stored.txt"; : > "$STORED"
mkdir -p "$RUNDIR"

clean() { echo "${1%%\?*}"; }

# The manifest. A successful run keeps the one task_pack.sh wrote, byte for byte, unless the
# required data.csv.gz was not stored (inventory mode), which turns it failed. A failed run (or a
# run with no pack manifest) gets the minimal record below, merged over any pack fields.
write_manifest() {
  STATUS="$STATUS" REASON="$REASON" STARTED_AT="${STARTED_AT:-}" python3 -I -c '
import json, os, hashlib, datetime, sys
inp, stored, ticket = sys.argv[1:4]
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
p = os.path.join(inp, "run_manifest.json")
try: m = json.load(open(p))
except Exception: m = {}
names = sorted(l.strip() for l in open(stored) if l.strip())
status = os.environ["STATUS"]
if status == "ok" and m.get("manifest_version") and m.get("status") in ("ok", "failed"):
    # the pack manifest: push it unchanged, unless a required output never made it
    if m["status"] == "ok" and m.get("mode", "inv") == "inv" and "data.csv.gz" not in names:
        m["status"] = "failed"; m["stop_reason"] = "required output missing: data.csv.gz"
        json.dump(m, open(p, "w"), indent=2, sort_keys=True)
    sys.exit(0)
try: tk = json.load(open(ticket))
except Exception: tk = {}
def info(n):
    h = hashlib.sha256(); b = 0
    with open(os.path.join(inp, n), "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""): h.update(c); b += len(c)
    return {"name": n, "bytes": b, "sha256": h.hexdigest()}
m.update({"manifest_version": 1, "status": os.environ["STATUS"],
          "stop_reason": os.environ["REASON"].encode("ascii", "replace").decode()[:110],
          "run_id": tk.get("run_id") or os.environ.get("RUN_ID") or m.get("run_id"),
          "outputs": [info(n) for n in names],
          "started_at": os.environ.get("STARTED_AT") or m.get("started_at") or now,
          "finished_at": now})
for k, v in (("mode", "inv"), ("image", {"name": os.environ.get("MOVES_IMAGE"), "digest": os.environ.get("MOVES_IMAGE_DIGEST")}),
             ("moves", {"commit": None, "default_db": None}), ("runspec", None),
             ("inputs", []), ("timings", {}), ("host", {"cpus": os.cpu_count(), "mem_bytes": 0})):
    m.setdefault(k, v)
json.dump(m, open(p, "w"), indent=2, sort_keys=True)
' "$IN" "$STORED" "$T"
}

# The manifest decides the final status (pack may have written failed; a missing required output flips it).
sync_status() { STATUS=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$IN/run_manifest.json" 2>/dev/null || echo "$STATUS"); }

# PUT one file with the ticket's headers; echoes the HTTP status.
put_file() {  # put_file <file> <put_url> <content_type> <headers.txt>
  local -a H=(-H "Content-Type: $3")
  while IFS= read -r l; do [ -n "$l" ] && H+=(-H "$l"); done < "$4"
  curl -sS --retry 0 -X PUT "${H[@]}" -T "$1" -o /dev/null -w '%{http_code}' "$2" 2>/dev/null
}

refetch() {
  local code i
  for i in 1 2 3; do
    code=$(curl -sS --retry 0 -o "$T.new" -w '%{http_code}' "$TICKET_URL" 2>/dev/null)
    [ "$code" = 200 ] && { mv -f "$T.new" "$T"; chmod 600 "$T"; return 0; }
    sleep $((2 ** i * SLEEP_SCALE))
  done
  return 1
}

if [ "$MOVES_IO" = "sync" ]; then
  [ -n "$MOVES_SYNC_REMOTE" ] || { echo "---MOVES_SYNC_REMOTE is not set"; exit 5; }
  : > "$STORED"
  for n in data.csv.gz moveslog.txt.gz replication.tar.xz; do [ -f "$IN/$n" ] && echo "$n" >> "$STORED"; done
  write_manifest; sync_status
  rclone --config /dev/null copy "$IN" "$MOVES_SYNC_REMOTE/out" --exclude run_manifest.json \
    --include 'data.csv.gz' --include 'moveslog.txt.gz' --include 'replication.tar.xz' || exit 4
  rclone --config /dev/null copyto "$IN/run_manifest.json" "$MOVES_SYNC_REMOTE/out/run_manifest.json" || exit 4
  [ "$STATUS" = ok ]; exit $?
fi

# 1. Fresh links (a run is long; the start-of-run links may have expired).
refetch || { echo "---pre-push ticket fetch failed from $(clean "$TICKET_URL")"; exit 4; }

list_outputs() {
  python3 -I -c '
import json, sys
for o in json.load(open(sys.argv[1]))["outputs"]:
    print(o["name"], o["put_url"], o["content_type"], "1" if o["required"] else "0", sep="\t")' "$T"
}
headers_for() {  # one "Key: value" per line
  python3 -I -c '
import json, sys
for o in json.load(open(sys.argv[1]))["outputs"]:
    if o["name"] == sys.argv[2]:
        for k, v in (o.get("headers") or {}).items(): print(k + ": " + v)' "$T" "$1"
}

# 2. Every output but the manifest, in ticket order.
FAILED_REASON=""
while IFS=$'\t' read -r name url ctype req; do
  [ "$name" = run_manifest.json ] && continue
  if [ ! -f "$IN/$name" ]; then
    echo "---not produced: $name"
    [ "$req" = 1 ] && [ -z "$FAILED_REASON" ] && FAILED_REASON="required output missing: $name"
    continue
  fi
  headers_for "$name" > "$RUNDIR/h.txt"
  code=000; refetched=0
  for i in 1 2 3; do
    code=$(put_file "$IN/$name" "$url" "$ctype" "$RUNDIR/h.txt")
    [[ "$code" =~ ^2 ]] && break
    if [[ "$code" =~ ^(400|401|403)$ ]] && [ "$refetched" = 0 ] && refetch; then
      refetched=1
      url=$(list_outputs | awk -F'\t' -v n="$name" '$1==n {print $2}')
      continue
    fi
    sleep $((2 ** i * SLEEP_SCALE))
  done
  if [[ "$code" =~ ^2 ]]; then
    echo "$name" >> "$STORED"; echo "---pushed $name"
  else
    echo "---push failed: $name HTTP $code"
    [ "$req" = 1 ] && [ -z "$FAILED_REASON" ] && FAILED_REASON="push failed: $name HTTP $code"
  fi
done < <(list_outputs)

if [ -n "$FAILED_REASON" ] && [ "$STATUS" = ok ]; then STATUS=failed; REASON="$FAILED_REASON"; fi
rm -f "$RUNDIR/h.txt"

# 3. The manifest, PUT last and once.
write_manifest; sync_status
read -r murl mctype < <(list_outputs | awk -F'\t' '$1=="run_manifest.json" {print $2, $3}')
if [ -z "$murl" ]; then echo "---ticket lists no run_manifest.json"; exit 4; fi
headers_for run_manifest.json > "$RUNDIR/h.txt"
code=000
for i in 1 2 3; do
  code=$(put_file "$IN/run_manifest.json" "$murl" "$mctype" "$RUNDIR/h.txt")
  [[ "$code" =~ ^2 ]] && break
  sleep $((2 ** i * SLEEP_SCALE))
done
rm -f "$RUNDIR/h.txt"
[[ "$code" =~ ^2 ]] || { echo "---manifest push failed: HTTP $code"; exit 4; }
echo "---pushed run_manifest.json (status $STATUS)"

case "$FAILED_REASON" in "") ;; "required output missing"*) exit 1 ;; *) exit 4 ;; esac
[ "$STATUS" = ok ]
