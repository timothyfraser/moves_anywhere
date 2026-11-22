#!/bin/bash
# quickstart_from_readme.sh: run the README "Quick start" of MOVES Anywhere as a new user would.
# The r, json and bash blocks are taken from the README's "## Quick start" section, so the test cannot drift
# from the page. Run from the repository root. Work happens in $QS_DIR (default $RUNNER_TEMP/quickstart or a
# temp folder). Exit 0 only if the bash step exits 0 AND inputs/data.csv exists AND run_manifest.json says ok.
# Usage: bash .github/scripts/quickstart_from_readme.sh [--extract-only]
set -u
EXTRACT_ONLY=0
[ "${1:-}" = "--extract-only" ] && EXTRACT_ONLY=1
REPO="$(pwd)"
if [ ! -f "$REPO/README.md" ] || [ ! -f "$REPO/moves_anywhere/run.sh" ]; then
  echo "run from the repository root"; exit 2
fi
Q="${QS_DIR:-${RUNNER_TEMP:-$(mktemp -d)}/quickstart}"
rm -rf "$Q"; mkdir -p "$Q"
say() { echo "$(date -u +%H:%M:%S) $*"; }

say "extract the Quick start blocks from README.md"
python3 -I - "$REPO/README.md" "$Q" <<'PY'
import re, sys, os
text = open(sys.argv[1], encoding="utf-8").read()
out = sys.argv[2]
sec = text.split("\n## Quick start", 1)[1].split("\n## ", 1)[0]
blocks = re.findall(r"```\s*(\w+)\s*\n(.*?)```", sec, flags=re.S)
print("blocks:", [k.lower() for k, _ in blocks])
pick = lambda kind: [b for k, b in blocks if k.lower() == kind]
r, j, sh = pick("r"), pick("json"), pick("bash")
assert len(r) == 1 and len(j) == 1 and len(sh) == 1, "expected one r, one json and one bash block"
for name, body in (("step_r.R", r[0]), ("step_json.json", j[0]), ("step_run.sh", sh[0])):
    open(os.path.join(out, name), "w", encoding="utf-8", newline="\n").write(body)
PY
if [ $? -ne 0 ] || [ ! -f "$Q/step_r.R" ]; then say "FAIL: could not extract the three blocks"; exit 4; fi

if [ "$EXTRACT_ONLY" = 1 ]; then
  for f in step_r.R step_json.json step_run.sh; do echo "--- $f"; cat "$Q/$f"; done
  echo "extracted into $Q"; exit 0
fi

cd "$Q" || exit 2

say "step 1: the R block"; cat step_r.R
Rscript step_r.R > r.log 2>&1; rc=$?
say "R exit $rc"
if [ $rc -ne 0 ]; then tail -20 r.log; say "FAIL: R block"; exit 5; fi
if [ ! -s inputs/rs_custom.xml ]; then say "FAIL: inputs/rs_custom.xml missing"; exit 5; fi

say "step 2: save the json block as inputs/parameters.json"
cp step_json.json inputs/parameters.json
python3 -I -c "import json; print('parameters.json keys:', sorted(json.load(open('inputs/parameters.json'))))" || { say "FAIL: json"; exit 5; }
say "inputs holds: $(ls inputs | tr '\n' ' ')"

say "step 4: the bash block, with moves_anywhere/ taken from the checkout"
sed -i "s#moves_anywhere/#$REPO/moves_anywhere/#g" step_run.sh; cat step_run.sh
t0=$(date +%s)
timeout 1500 bash step_run.sh > run.log 2>&1
rc=$?
say "run exit $rc after $(( $(date +%s) - t0 )) s"
tail -8 run.log | cut -c1-220
say "inputs now holds: $(ls inputs | tr '\n' ' ')"

status="missing"
if [ -f inputs/run_manifest.json ]; then
  status=$(python3 -I -c "import json; print(json.load(open('inputs/run_manifest.json', encoding='utf-8')).get('status'))")
fi
rows=0
if [ -s inputs/data.csv ]; then rows=$(( $(wc -l < inputs/data.csv) - 1 )); fi

say "SUMMARY: run.sh exit=$rc | manifest status=$status | data.csv rows=$rows"
ok=1
[ $rc -eq 0 ] || ok=0
[ -s inputs/data.csv ] || ok=0
[ "$status" = "ok" ] || ok=0
if [ $ok -eq 1 ]; then say "QUICKSTART PASS"; exit 0; fi
say "QUICKSTART FAIL"; exit 1
