#!/bin/bash
# tests/test_comments_only_selftest.sh: proves tests/test_comments_only.sh passes comment-only
# changes and fails code changes, in a throwaway git repository.
# Usage: bash moves_anywhere/tests/test_comments_only_selftest.sh
# Needs: git, diff, sed. Touches nothing outside its own temporary folder, which it removes.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checker="$here/test_comments_only.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS  $1"; }
bad() { fail=$((fail+1)); echo "FAIL  $1"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 2
g() { git -c core.autocrlf=false -c user.name=selftest -c user.email=selftest@example.invalid -c commit.gpgsign=false "$@"; }
g init -q -b base . || exit 2

# 1. A small base: one R script, one shell script, one Python script ###########
cat > adapt_x.R <<'EOF'
adapt_x = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  # Get your list of key values from your runspec
  rs = catr::translate_rs(.runspec = .runspec)
  table = "x"
  return(table)
}
EOF
cat > task_x.sh <<'EOF'
#/bin/bash
# task_x.sh
cd "/cat/EPA_MOVES_Model" || { echo "Failed to change directory"; exit 1; }
echo done
EOF
cat > tool_x.py <<'EOF'
"""Old docstring."""
import sys
print(sys.argv)
EOF
g add -A && g commit -q -m base || exit 2

# Run the checker on a fresh branch from base after applying a change.
# expect: 0 (pass) or 1 (fail); pattern: text the output must contain.
case_run() {
  local name="$1" expect="$2" pattern="$3"; shift 3
  g checkout -q -B "case" base || exit 2
  "$@"
  g add -A && g commit -q -m "$name" || exit 2
  out="$(bash "$checker" base 2>&1)"; code=$?
  if [ "$code" = "$expect" ] && printf '%s\n' "$out" | grep -qF -- "$pattern"; then
    ok "$name (exit $code)"
  else
    bad "$name (exit $code, wanted $expect and '$pattern')"; printf '%s\n' "$out" | sed 's/^/      /'
  fi
}

# 2. The cases ####################################################################
# (a) comment-only change: a header and a numbered step added, code untouched
a_change() {
  { printf '# adapt_x.R ####\n#\n# What:      Adapter for x\n####\n\n'
    sed 's|^  # Get your list|  # 1. Read the runspec ####\n  # Get your list|' adapt_x.R; } > t && mv t adapt_x.R
}
case_run "(a) comment-only change passes" 0 "PASS 1 files" a_change

# (b) one-token code change: "x" -> "y"
b_change() { sed -i 's|table = "x"|table = "y"|' adapt_x.R; }
case_run "(b) one-token code change fails" 1 'FAIL adapt_x.R: code line changed: +  table = "y"' b_change

# (c) shebang fix: #/bin/bash -> #!/bin/bash, plus header lines
c_change() { sed -i -e '1s|^#/bin/bash$|#!/bin/bash|' -e '2s|$| ####\n#\n# Exits:     1 if the folder is missing|' task_x.sh; }
case_run "(c) shebang fix passes" 0 "PASS 1 files" c_change

# (d) Python docstring change counts as code
d_change() { sed -i 's|Old docstring|New docstring|' tool_x.py; }
case_run "(d) Python docstring change fails" 1 'FAIL tool_x.py: code line changed: +"""New docstring."""' d_change

# (e) new file with code fails; new file with only comments passes
e_change() { printf '#!/bin/bash\necho hi\n' > new.sh; printf '# notes only\n' > new_notes.R; }
case_run "(e) new code file fails" 1 'FAIL new.sh: code line changed: +echo hi' e_change

# (f) deleted and renamed files fail
f_change() { g rm -q tool_x.py; g mv task_x.sh task_y.sh; }
case_run "(f) delete fails" 1 "FAIL tool_x.py: file deleted" f_change
case_run "(f) rename fails" 1 "FAIL task_x.sh: file renamed to task_y.sh" f_change

# (g) files out of scope are listed, not checked
g_change() { echo "notes" > NOTES.md; }
case_run "(g) Markdown listed as OTHER" 0 "OTHER NOTES.md" g_change

cd / && echo "selftest: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
