#!/bin/bash
# tests/test_comments_only.sh: proves a change touched only comment lines.
# Usage: bash moves_anywhere/tests/test_comments_only.sh [BASE_REF]
# BASE_REF defaults to origin/main. Run it from anywhere inside the repository.
#
# For every file that differs between BASE_REF and HEAD (from their merge base, as a pull
# request shows it) and ends in .R, .r, .sh or .py, or is named Dockerfile:
#   - modified: the BASE and HEAD versions must be identical once full-line comments (first
#     non-space character `#`, which covers shebangs, roxygen `#'` lines and the
#     `#/bin/bash` -> `#!/bin/bash` fix) and blank lines are removed. Anything else fails.
#   - added: fails unless the new file holds only comments and blank lines.
#   - deleted, renamed, copied or changed type: fails.
# Python module docstrings are code here: a docstring change fails. Put header text in `#` lines.
# Known limit: a line that starts with `#` inside a multi-line string or heredoc is treated as a
# comment. Review such files by eye.
# Other changed files are listed as `OTHER <file>` and are not checked.
# COMMENTS_ONLY_SKIP: space-separated paths to leave out, each printed as `SKIP <file>`.
# Exits: 0 when every checked file passes (`PASS n files`); 1 on any failure; 2 on a usage error.

base="${1:-origin/main}"
git rev-parse --verify --quiet "$base^{commit}" > /dev/null || { echo "unknown BASE_REF: $base" >&2; exit 2; }
root="$(git rev-parse --show-toplevel)" || exit 2
cd "$root" || exit 2
mb="$(git merge-base "$base" HEAD)" || { echo "no merge base between $base and HEAD" >&2; exit 2; }

# Drop full-line comments and blank lines; keep every other byte as it is.
strip() { sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d'; }

in_scope() {
  case "${1##*/}" in
    Dockerfile|*.R|*.r|*.sh|*.py) return 0 ;;
    *) return 1 ;;
  esac
}

skipped() {
  local s
  for s in $COMMENTS_ONLY_SKIP; do [ "$s" = "$1" ] && return 0; done
  return 1
}

n=0; failed=0
tmpf="$(mktemp)"; trap 'rm -f "$tmpf"' EXIT
fail() { failed=$((failed+1)); echo "FAIL $1: $2"; }

while IFS=$'\t' read -r status path1 path2; do
  [ -n "$status" ] || continue
  if ! in_scope "$path1" && { [ -z "$path2" ] || ! in_scope "$path2"; }; then
    echo "OTHER $path1${path2:+ -> $path2}"; continue
  fi
  if skipped "$path1"; then echo "SKIP $path1"; continue; fi
  n=$((n+1))
  case "$status" in
    M)
      diff --unchanged-line-format= --old-line-format='-%L' --new-line-format='+%L' \
        <(git show "$mb:$path1" | strip) <(git show "HEAD:$path1" | strip) > "$tmpf" 2>&1
      if [ -s "$tmpf" ]; then
        failed=$((failed+1))
        while IFS= read -r line; do echo "FAIL $path1: code line changed: $line"; done < "$tmpf"
      else
        echo "ok   $path1"
      fi
      ;;
    A)
      left="$(git show "HEAD:$path1" | strip)"
      if [ -n "$left" ]; then
        failed=$((failed+1))
        printf '%s\n' "$left" | while IFS= read -r line; do echo "FAIL $path1: code line changed: +$line"; done
      else
        echo "ok   $path1 (new, comments only)"
      fi ;;
    D)  fail "$path1" "file deleted" ;;
    R*) fail "$path1" "file renamed to $path2" ;;
    C*) fail "$path2" "file copied from $path1" ;;
    T)  fail "$path1" "file type changed" ;;
    *)  fail "$path1" "unexpected change status $status" ;;
  esac
done < <(git diff --no-ext-diff --name-status -M "$mb" HEAD)

if [ "$failed" -gt 0 ]; then
  echo "FAILED $failed of $n files"
  exit 1
fi
echo "PASS $n files"
exit 0
