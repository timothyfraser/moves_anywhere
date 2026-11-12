#!/bin/bash
# test_readme_commands.sh #####################################################
#
# What:      Checks that every command shown in README.md runs, as far as it can without Docker or the network.
# Does:      Takes each fenced code block out of README.md and checks each command in it. R blocks are
#            parsed. The R install commands are replayed from the files they would download (built and
#            installed into a temporary library); the other R commands then run in an empty folder, as a
#            new user would run them. run.sh and run.ps1 get a syntax check and dry runs that stop before
#            Docker (docker is replaced by a stand-in that refuses). Docker, MOVES and downloads never run
#            here: each prints SKIP and why. A command this test has no rule for fails.
# Called by: Developer tool: release checklist item 25; step readme of tests/run_gate.sh. Not run by launch.sh.
# Reads:     README.md (or --readme FILE), moves_anywhere/run.sh, moves_anywhere/run.ps1, catr/
# Writes:    a temporary folder, removed on exit unless --keep; nothing in the working tree
# Needs:     bash, git, R (Rscript) with catr's dependencies installed; PowerShell for the PowerShell command
# Exits:     0 if every check passed or was skipped with a reason; 1 if any check failed; 2 on a usage error
# Usage: bash moves_anywhere/tests/test_readme_commands.sh [--readme FILE] [--keep]
###############################################################################

set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1

README=""; KEEP=0
usage() { sed -n 's/^# \(Usage: .*\)$/\1/p' "$0"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --readme) [ $# -ge 2 ] || { usage >&2; exit 2; }; README="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "test_readme_commands.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
done

# 1. Where we are ####
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$here/../.." && pwd)"
README="${README:-$TOP/README.md}"
[ -f "$README" ] || { echo "test_readme_commands.sh: no such file: $README" >&2; exit 2; }
NAME="$(basename "$README")"
# Native programs (R, PowerShell, Python) on Windows need C:/... paths, not /c/... or /tmp/...
native() { if command -v cygpath > /dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
winpath() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
TOPN="$(native "$TOP")"
TMP_POSIX="$(mktemp -d)"
TMP="$(native "$TMP_POSIX")"
cleanup() { if [ "$KEEP" = 1 ]; then echo "kept: $TMP"; else rm -rf "$TMP_POSIX"; fi; }
trap cleanup EXIT
T0=$SECONDS

PS=""
for p in powershell pwsh; do command -v "$p" > /dev/null 2>&1 && { PS="$(command -v "$p")"; break; }; done
PY=""
for p in python3 python; do
  if command -v "$p" > /dev/null 2>&1 && "$p" -c 'import sys' < /dev/null > /dev/null 2>&1; then PY="$p"; break; fi
done

# The docker stand-in: first on PATH in every dry run. It records its arguments and refuses (exit 1), so no
# container can start even if a script got past its own input checks. PATH needs the /tmp/... spelling.
SHIM_POSIX="$TMP_POSIX/shim"; SHIM_NAME="$(basename "$TMP_POSIX")"
mkdir -p "$SHIM_POSIX"
printf '#!/bin/sh\n# docker stand-in for test_readme_commands.sh: records the call and refuses\necho "$*" >> "$(dirname "$0")/calls.txt"\nexit 1\n' > "$SHIM_POSIX/docker"
printf '@echo off\r\nrem docker stand-in for test_readme_commands.sh: records the call and refuses\r\necho %%*>>"%%~dp0calls.txt"\r\nexit /b 1\r\n' > "$SHIM_POSIX/docker.cmd"
chmod +x "$SHIM_POSIX/docker"

# 2. Reporting ####
NPASS=0; NFAIL=0; NSKIP=0; CUR=""; FAILED=()
NORULE="no rule for this command, so it was not run: add one to tests/test_readme_commands.sh"
# begin <label>: starts the checks of one command
begin() { CUR="$1"; printf '\n--- %s\n' "$1"; }
# report <PASS|FAIL|SKIP|NOTE> <message>
report() {
  local st="$1"; shift
  printf '%-4s  %s\n' "$st" "$*"
  case "$st" in
    PASS) NPASS=$((NPASS + 1)) ;;
    FAIL) NFAIL=$((NFAIL + 1)); FAILED+=("$CUR: $*") ;;
    SKIP) NSKIP=$((NSKIP + 1)) ;;
  esac
  return 0
}

# dry <folder> <command...>: runs a command in <folder> with the docker stand-in first on PATH, no input,
# and an image name that does not exist; its output goes to $TMP/dry.log
dry() {
  local d="$1"; shift
  : > "$SHIM_POSIX/calls.txt"
  ( cd "$d" && PATH="$SHIM_POSIX:$PATH" MOVES_IMAGE="moves-anywhere-readme-test:none" "$@" ) < /dev/null > "$TMP/dry.log" 2>&1
}
calls() { tr -d '\r' < "$SHIM_POSIX/calls.txt" | tr '\n' ';'; }
first_line() { grep -m 1 . "$TMP/dry.log" | tr -d '\r'; }

# shim_first <program>: does that program (bash, or a PowerShell) find the docker stand-in first on PATH?
shim_first() {
  local found
  case "$(basename "$1")" in
    bash)
      found="$(PATH="$SHIM_POSIX:$PATH" bash -c 'command -v docker' < /dev/null 2> /dev/null)"
      [ "$found" = "$SHIM_POSIX/docker" ] ;;
    *)
      found="$(PATH="$SHIM_POSIX:$PATH" "$1" -NoProfile -NonInteractive -Command '(Get-Command docker).Source' < /dev/null 2> /dev/null | tr -d '\r')"
      case "$found" in *"$SHIM_NAME"*) return 0 ;; *) return 1 ;; esac ;;
  esac
}

# first_folder <args...>: the first argument that is not an option or an option's value
first_folder() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --image|--cpus|--memory|-Image|-Cpus|-Memory) shift; [ $# -gt 0 ] && shift ;;
      -*) shift ;;
      *) printf '%s' "$1"; return ;;
    esac
  done
}

# commands_of <block file>: one command per line, as "<line in block><tab><command>": blank lines and
# comments dropped, backslash continuations joined, "$ " prompts removed
commands_of() {
  awk '{
    sub(/\r$/, "")
    if (cont == "") { start = NR; line = $0 } else { line = cont " " $0 }
    if (line ~ /\\$/) { sub(/\\$/, "", line); cont = line; next }
    cont = ""
    sub(/^[ \t]*\$[ \t]+/, "", line); sub(/^[ \t]+/, "", line)
    sub(/[ \t]+#.*$/, "", line); sub(/[ \t]+$/, "", line)
    if (line == "" || line ~ /^#/) next
    print start "\t" line
  }' "$1"
}

# 3. The fenced blocks ####
# blocks/index.tsv: block number, line of the opening fence, language; blocks/<n>.txt: the block's lines
mkdir -p "$TMP/blocks"
: > "$TMP/blocks/index.tsv"
awk -v dir="$TMP/blocks" '
  { sub(/\r$/, "") }
  !inb && /^[ \t]*```/ {
    inb = 1; n++; lang = tolower($0)
    sub(/^[ \t]*`+[ \t]*/, "", lang); sub(/[ \t,].*$/, "", lang); gsub(/[{}]/, "", lang)
    f = dir "/" n ".txt"; printf "" > f
    printf "%d\t%d\t%s\n", n, NR, lang >> (dir "/index.tsv")
    next
  }
  inb && /^[ \t]*```[ \t]*$/ { inb = 0; close(f); next }
  inb { print > f }
  END { if (inb) printf "%d\t%d\t%s\n", n, NR, "(unclosed)" >> (dir "/index.tsv") }
' "$README"
NBLOCKS=$(grep -c . "$TMP/blocks/index.tsv")
echo "test_readme_commands.sh: $NBLOCKS fenced blocks in $NAME (Docker, MOVES and downloads are never run)"

# 4. R commands ####
# The R half: written out here so the test stays one file. It prints one line per result:
# CMD, PASS, FAIL, SKIP or NOTE, a tab, then the message.
r_half() {
cat <<'REOF'
# readme_r.R: the R half of moves_anywhere/tests/test_readme_commands.sh, which writes it to its
# temporary folder and runs it.
#   check: parses the R blocks, checks each command, replays the install commands offline
#   run:   runs the commands that are safe offline (library, dir.create, custom_rs) in an empty folder
main = function(a){
  mode = a[1]; name = a[2]; top = a[3]; tmp = a[4]
  blocks = utils::read.delim(a[5], header = FALSE, colClasses = "character", col.names = c("fence", "path"))
  norule = "no rule for this command, so it was not run: add one to tests/test_readme_commands.sh"
  emit = function(st, msg){ cat(st, "\t", gsub("[\t\r\n]+", " ", msg), "\n", sep = "") }
  short = function(x, n = 150){ if(nchar(x) > n){ paste0(substr(x, 1, n - 3), "...") }else{ x } }
  kind = function(e){
    if(!is.call(e)){ return("unknown") }
    f = paste(deparse(e[[1]]), collapse = "")
    if(f %in% c("library", "require")){ return("load") }
    if(f %in% c("dir.create")){ return("base") }
    if(f %in% c("custom_rs", "catr::custom_rs")){ return("custom_rs") }
    if(f %in% c("remotes::install_github", "devtools::install_github")){ return("install_github") }
    if(f %in% c("remotes::install_url", "devtools::install_url")){ return("install_url") }
    if(f %in% c("install.packages")){ return("cran") }
    "unknown"
  }
  # arg(): an argument of a call, by name, or else by position among the unnamed ones
  arg = function(e, nm, pos = NA){
    x = as.list(e)[-1]
    n = names(x); if(is.null(n)){ n = rep("", length(x)) }
    if(nm %in% n){ return(x[[match(nm, n)]]) }
    u = which(n == "")
    if(!is.na(pos) && length(u) >= pos){ return(x[[u[pos]]]) }
    NULL
  }
  # commands(): every top-level call in every R block, with its README line and its source text
  commands = function(){
    out = list()
    for(i in seq_len(nrow(blocks))){
      fence = as.integer(blocks$fence[i])
      ex = tryCatch(parse(file = blocks$path[i], keep.source = TRUE), error = function(err) err)
      if(inherits(ex, "error")){
        msg = gsub(blocks$path[i], "block", conditionMessage(ex), fixed = TRUE)
        out[[length(out) + 1]] = list(line = fence, text = "", e = NULL, err = msg)
        next
      }
      sr = attr(ex, "srcref")
      for(j in seq_along(ex)){
        out[[length(out) + 1]] = list(line = fence + as.integer(sr[[j]][1]),
          text = paste(trimws(as.character(sr[[j]])), collapse = " "), e = ex[[j]], err = NULL)
      }
    }
    out
  }
  # rcmd(): runs R CMD <args>; ok and the combined output
  rcmd = function(args, wd = NULL){
    if(!is.null(wd)){ old = setwd(wd); on.exit(setwd(old)) }
    out = suppressWarnings(system2(file.path(R.home("bin"), "R"), args, stdout = TRUE, stderr = TRUE))
    st = attr(out, "status")
    list(ok = is.null(st) || st == 0, log = out)
  }
  last = function(log){ x = trimws(log); x = x[nzchar(x)]; short(paste(utils::tail(x, 2), collapse = " / "), 300) }

  # 1. check ####
  if(mode == "check"){
    libs = character(0)
    for(k in commands()){
      if(is.null(k$e)){
        emit("CMD", sprintf("%s:%d (r block)", name, k$line))
        emit("FAIL", paste("does not parse as R:", short(k$err, 300)))
        next
      }
      emit("CMD", sprintf("%s:%d (r) %s", name, k$line, short(k$text, 120)))
      emit("PASS", "parses as R")
      kd = kind(k$e)
      if(kd %in% c("load", "base", "custom_rs")){ emit("NOTE", "runs below, in an empty folder"); next }
      if(kd == "cran"){ emit("SKIP", "needs the network (CRAN), so it was not run"); next }
      if(kd == "unknown"){ emit("FAIL", norule); next }
      d = file.path(tmp, sprintf("install_%d", k$line)); dir.create(d)
      if(kd == "install_github"){
        repo = arg(k$e, "repo", 1); sub = arg(k$e, "subdir"); if(is.null(sub)){ sub = "" }
        if(!is.character(repo) || !is.character(sub) || !nzchar(sub)){ emit("FAIL", paste("only a plain repo and subdir have a rule:", norule)); next }
        emit("SKIP", sprintf("the download from github.com/%s needs the network: replayed from %s/ in this checkout instead", repo, sub))
        src = file.path(top, sub)
        if(!file.exists(file.path(src, "DESCRIPTION"))){ emit("FAIL", sprintf("%s/DESCRIPTION is not in this checkout", sub)); next }
        dsc = read.dcf(file.path(src, "DESCRIPTION"), fields = c("Package", "Version"))
        emit("PASS", sprintf("%s/ holds the %s package, version %s", sub, dsc[1, 1], dsc[1, 2]))
        # remotes builds the package, then installs what it built: do the same, from a copy
        file.copy(src, d, recursive = TRUE)
        b = rcmd(c("CMD", "build", "--no-build-vignettes", "--no-manual", "--no-resave-data", shQuote(file.path(d, basename(src)))), wd = d)
        built = list.files(d, pattern = "[.]tar[.]gz$", full.names = TRUE)
        if(!b$ok || length(built) != 1){ emit("FAIL", paste("R CMD build fails:", last(b$log))); next }
        emit("PASS", sprintf("builds offline (R CMD build), as remotes would: %s", basename(built)))
        what = sprintf("%s from %s/", dsc[1, 1], sub)
        pkgfile = built
      }else{
        url = arg(k$e, "url", 1)
        if(!is.character(url)){ emit("FAIL", paste("only a plain URL has a rule:", norule)); next }
        m = regmatches(url, regexec("^https://github[.]com/[^/]+/[^/]+/raw/[^/]+/(.+)$", url))[[1]]
        if(length(m) != 2){ m = regmatches(url, regexec("^https://raw[.]githubusercontent[.]com/[^/]+/[^/]+/[^/]+/(.+)$", url))[[1]] }
        if(length(m) != 2){ emit("FAIL", paste("this URL is not a file in this repository on GitHub:", norule)); next }
        rel = m[2]
        emit("SKIP", sprintf("the download from %s needs the network: replayed from %s in this checkout instead", sub("^https://([^/]+)/.*$", "\\1", url), rel))
        tracked = system2("git", c("-C", shQuote(top), "ls-files", "--error-unmatch", "--", shQuote(rel)), stdout = FALSE, stderr = FALSE) == 0
        if(!tracked){ emit("FAIL", sprintf("%s is not committed, so the URL has nothing to serve", rel)); next }
        emit("PASS", sprintf("%s is committed", rel))
        fn = regmatches(basename(rel), regexec("^([A-Za-z][A-Za-z0-9.]*)_([0-9][0-9.-]*)[.]tar[.]gz$", basename(rel)))[[1]]
        if(length(fn) != 3){ emit("FAIL", "the file name is not <package>_<version>.tar.gz"); next }
        x = tryCatch(suppressWarnings({
          utils::untar(file.path(top, rel), files = paste0(fn[2], "/DESCRIPTION"), exdir = d)
          read.dcf(file.path(d, fn[2], "DESCRIPTION"), fields = c("Package", "Version"))
        }), error = function(err) NULL)
        if(is.null(x) || !identical(unname(x[1, 1]), fn[2]) || !identical(unname(x[1, 2]), fn[3])){
          emit("FAIL", sprintf("its DESCRIPTION does not say %s %s, as the file name does", fn[2], fn[3])); next
        }
        emit("PASS", sprintf("its DESCRIPTION says %s %s, as the file name does", fn[2], fn[3]))
        what = sprintf("%s from %s", fn[2], rel)
        pkgfile = file.path(top, rel)
      }
      lib = file.path(d, "lib"); dir.create(lib)
      r = rcmd(c("CMD", "INSTALL", "--no-docs", "--no-multiarch", paste0("--library=", shQuote(lib)), shQuote(pkgfile)))
      if(!r$ok){ emit("FAIL", paste("R CMD INSTALL fails:", last(r$log))); next }
      emit("PASS", "installs offline into a temporary library, and loads")
      libs = c(libs, paste(what, lib, sep = "\t"))
    }
    con = file(file.path(tmp, "r_libs.tsv"), "wb"); writeLines(libs, con); close(con)
  }

  # 2. run ####
  if(mode == "run"){
    lib = a[6]; label = a[7]; wd = a[8]
    if(nzchar(lib)){ .libPaths(c(lib, .libPaths())) }
    setwd(wd)
    for(k in commands()){
      if(is.null(k$e)){ next }
      kd = kind(k$e)
      if(!kd %in% c("load", "base", "custom_rs")){ next }
      emit("CMD", sprintf("%s:%d (r, %s) %s", name, k$line, label, short(k$text, 120)))
      res = tryCatch({ utils::capture.output(v <- eval(k$e, globalenv())); list(ok = TRUE, v = v) },
                     error = function(err) list(ok = FALSE, msg = conditionMessage(err)))
      if(!res$ok){ emit("FAIL", paste("fails in an empty folder:", short(res$msg, 300))); next }
      if(kd == "load"){
        p = as.character(arg(k$e, "package", 1))
        if(!p %in% loadedNamespaces()){ emit("FAIL", sprintf("runs, but %s is not loaded", p)); next }
        emit("PASS", sprintf("runs: loads %s %s", p, as.character(utils::packageVersion(p))))
      }else if(kd == "base"){
        emit("PASS", "runs")
      }else{
        path = if(is.character(res$v) && length(res$v) == 1){ res$v }else{ "" }
        doc = if(nzchar(path) && file.exists(path)){ tryCatch(xml2::read_xml(path), error = function(err) NULL) }else{ NULL }
        if(is.null(doc) || xml2::xml_name(doc) != "runspec"){ emit("FAIL", sprintf("runs, but wrote no runspec (%s)", path)); next }
        geo = xml2::xml_attr(xml2::xml_find_first(doc, ".//geographicselections/geographicselection"), "key")
        yr = xml2::xml_attr(xml2::xml_find_first(doc, ".//timespan/year"), "key")
        g = arg(k$e, ".geoid"); y = arg(k$e, ".year")
        bad = c(if(!is.null(g) && !identical(geo, as.character(g))){ sprintf("geoid %s, not %s", geo, g) },
                if(!is.null(y) && !identical(yr, as.character(y))){ sprintf("year %s, not %s", yr, y) })
        if(length(bad)){ emit("FAIL", paste("runs, but the runspec says", paste(bad, collapse = " and "))); next }
        emit("PASS", sprintf("runs: writes %s, a runspec for geoid %s in %s", path, geo, yr))
      }
    }
  }
}
main(commandArgs(trailingOnly = TRUE))
REOF
}

# relay_r <mode> [args...]: runs the R half and turns its lines into report lines
relay_r() {
  local mode="$1" line st msg rc=""; shift
  while IFS= read -r line; do
    line="${line%$'\r'}"; st="${line%%$'\t'*}"; msg="${line#*$'\t'}"
    case "$st" in
      CMD) begin "$msg" ;;
      PASS|FAIL|SKIP|NOTE) report "$st" "$msg" ;;
      RC) rc="$msg" ;;
      *) printf '      %s\n' "$line" ;;
    esac
  done < <(Rscript "$TMP/readme_r.R" "$mode" "$NAME" "$TOPN" "$TMP" "$TMP/r_index.tsv" "$@" < /dev/null 2>> "$TMP/r_stderr.log"; printf 'RC\t%s\n' "$?")
  [ "$rc" = 0 ] || report FAIL "the R half stopped (exit $rc): $(tail -n 3 "$TMP/r_stderr.log" | tr '\r\n' '  ')"
}

# All R blocks first: the install commands put catr in place, then the other commands run in an empty
# folder. The run.sh and run.ps1 checks below reuse the first such folder.
: > "$TMP/r_index.tsv"
while IFS=$'\t' read -r n line lang; do
  [ "$lang" = r ] && printf '%s\t%s\n' "$line" "$TMP/blocks/$n.txt" >> "$TMP/r_index.tsv"
done < "$TMP/blocks/index.tsv"
QS="$TMP/quickstart1"
if [ -s "$TMP/r_index.tsv" ]; then
  echo; echo "=== R commands"
  if ! command -v Rscript > /dev/null 2>&1; then
    begin "$NAME (R blocks)"; report FAIL "Rscript is not on PATH, so the R commands cannot be checked"
  else
    r_half > "$TMP/readme_r.R"
    relay_r check
    [ -s "$TMP/r_libs.tsv" ] || printf 'your own R library\t\n' > "$TMP/r_libs.tsv"
    i=0
    while IFS=$'\t' read -r label lib; do
      lib="${lib%$'\r'}"; i=$((i + 1)); mkdir -p "$TMP/quickstart$i"
      relay_r run "$lib" "$label" "$TMP/quickstart$i"
    done < "$TMP/r_libs.tsv"
  fi
fi

# 5. Shell and PowerShell commands ####
# quickstart_check <folder> <command...>: the README command, run where the R commands wrote <folder>/rs_custom.xml.
# It should get past its input checks and stop at Docker, which is the stand-in.
quickstart_check() {
  local folder="$1" rc; shift
  if [ ! -f "$QS/$folder/rs_custom.xml" ]; then
    report SKIP "on the folder the R commands write: skipped, because they did not write $folder/rs_custom.xml (see above)"; return
  fi
  if ! shim_first "$1"; then
    report SKIP "on the folder the R commands write: skipped, because the docker stand-in is not first on PATH for $(basename "$1") here"; return
  fi
  dry "$QS" "$@"; rc=$?
  if [ "$rc" = 3 ] && [ "$(calls)" = "info;" ]; then
    report PASS "on the folder the R commands wrote, it gets as far as Docker: exit 3, $(first_line) (docker was the stand-in)"
  else
    report FAIL "on the folder the R commands wrote: exit $rc (wanted 3), docker calls: $(calls) $(first_line)"
  fi
}

# empty_check <dir> <folder> <command...>: the README command with an empty <folder>: it must stop before Docker
empty_check() {
  local dir="$1" folder="$2" rc; shift 2
  rm -rf "$dir"; mkdir -p "$dir/$folder"
  dry "$dir" "$@"; rc=$?
  if [ "$rc" = 2 ] && grep -q 'rs_custom.xml' "$TMP/dry.log" && [ -z "$(calls)" ]; then
    report PASS "with an empty $folder folder it stops before Docker: exit 2, $(first_line)"
  else
    report FAIL "with an empty $folder folder: exit $rc (wanted 2), docker calls: $(calls) $(first_line)"
  fi
}

# folder_ok <folder>: the dry runs make the README's inputs folder inside a temporary folder
folder_ok() {
  case "$1" in
    "") report FAIL "no inputs folder among the arguments: $NORULE"; return 1 ;;
    /*|*..*|~*|[A-Za-z]:*) report FAIL "the inputs folder is not a plain relative name: $NORULE"; return 1 ;;
  esac
}

# committed <path>: the path is in this checkout and committed (a fresh clone has it)
committed() {
  if [ ! -f "$TOP/$1" ]; then report FAIL "$1 is not in this checkout"; return 1; fi
  if git -C "$TOP" ls-files --error-unmatch -- "$1" < /dev/null > /dev/null 2>&1; then report PASS "$1 is committed"
  else report FAIL "$1 is not committed, so a fresh clone does not have it"; fi
}

# run_sh_checks <README arguments>: moves_anywhere/run.sh
run_sh_checks() {
  local sh="$TOP/moves_anywhere/run.sh" folder rc
  dry "$TMP" bash "$sh" --help; rc=$?
  if [ "$rc" = 0 ] && grep -q '<inputs-folder>' "$TMP/dry.log" && [ -z "$(calls)" ]; then
    report PASS "--help exits 0 and prints the usage"
  else
    report FAIL "--help: exit $rc (wanted 0), $(first_line)"
  fi
  folder="$(first_folder "$@")"
  folder_ok "$folder" || return
  empty_check "$TMP/empty_sh" "$folder" bash "$sh" "$@"
  quickstart_check "$folder" bash "$sh" "$@"
  report SKIP "the run itself starts Docker and MOVES: tests/run_gate.sh runs it (step fixture)"
}

# shell_command <README line> <command>
shell_command() {
  local w=() s
  begin "$NAME:$1 (bash) $2"
  read -r -a w <<< "$2"
  case "${w[0]}" in
    bash|sh)
      s="${w[1]:-}"
      [ -n "$s" ] || { report FAIL "$NORULE"; return; }
      committed "$s" || return
      if bash -n "$TOP/$s" 2> "$TMP/syntax.log"; then report PASS "bash -n finds no syntax error"
      else report FAIL "bash -n: $(head -n 1 "$TMP/syntax.log")"; fi
      case "$s" in
        moves_anywhere/run.sh) run_sh_checks ${w[2]+"${w[@]:2}"} ;;
        *) report FAIL "no rule to run $s offline, so it was not run: add one to tests/test_readme_commands.sh" ;;
      esac ;;
    docker) report SKIP "Docker: this test never runs Docker (tests/run_gate.sh builds and runs the image)" ;;
    curl|wget) report SKIP "needs the network, so it was not run" ;;
    git)
      case "${w[1]:-}" in
        clone|fetch|pull|push) report SKIP "needs the network, so it was not run" ;;
        *) report FAIL "$NORULE" ;;
      esac ;;
    *) report FAIL "$NORULE" ;;
  esac
}

# ps_command <README line> <command>: powershell ... -File <script> <arguments>
ps_command() {
  local w=() i f="" opts=() rest=() rel prog psfile folder
  begin "$NAME:$1 (powershell) $2"
  read -r -a w <<< "$2"
  prog="$(printf '%s' "${w[0]}" | tr '[:upper:]' '[:lower:]')"
  case "$prog" in
    powershell|powershell.exe|pwsh|pwsh.exe) ;;
    docker|docker.exe) report SKIP "Docker: this test never runs Docker (tests/run_gate.sh builds and runs the image)"; return ;;
    *) report FAIL "$NORULE"; return ;;
  esac
  for ((i = 1; i < ${#w[@]}; i++)); do
    if [ "$(printf '%s' "${w[i]}" | tr '[:upper:]' '[:lower:]')" = "-file" ]; then
      f="${w[i+1]:-}"
      [ "$i" -gt 1 ] && opts=("${w[@]:1:i-1}")
      [ $((i + 2)) -lt ${#w[@]} ] && rest=("${w[@]:i+2}")
      break
    fi
  done
  [ -n "$f" ] || { report FAIL "$NORULE"; return; }
  rel="$(printf '%s' "$f" | tr '\\' '/')"
  committed "$rel" || return
  if [ -z "$PS" ]; then report SKIP "no PowerShell on this machine, so $rel was not parsed or tried"; return; fi
  psfile="$(winpath "$TOP/$rel")"
  if RT_PS1="$psfile" "$PS" -NoProfile -NonInteractive -Command '$e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($env:RT_PS1, [ref]$null, [ref]$e); foreach ($x in $e) { Write-Output ("line " + $x.Extent.StartLineNumber + ": " + $x.Message) }; exit $e.Count' < /dev/null > "$TMP/ps.log" 2>&1; then
    report PASS "the PowerShell parser finds no syntax error"
  else
    report FAIL "the PowerShell parser: $(head -n 1 "$TMP/ps.log" | tr -d '\r')"
  fi
  case "$rel" in
    moves_anywhere/run.ps1) ;;
    *) report FAIL "no rule to run $rel offline, so it was not run: add one to tests/test_readme_commands.sh"; return ;;
  esac
  folder="$(first_folder ${rest[@]+"${rest[@]}"})"
  folder_ok "$folder" || return
  empty_check "$TMP/empty_ps" "$folder" "$PS" -NoProfile -NonInteractive ${opts[@]+"${opts[@]}"} -File "$psfile" ${rest[@]+"${rest[@]}"}
  quickstart_check "$folder" "$PS" -NoProfile -NonInteractive ${opts[@]+"${opts[@]}"} -File "$psfile" ${rest[@]+"${rest[@]}"}
  report SKIP "the run itself starts Docker and MOVES: tests/run_gate.sh runs the image (through run.sh)"
}

# py_block <block number> <fence line>
py_block() {
  begin "$NAME:$2 (python block)"
  if [ -z "$PY" ]; then
    report SKIP "no Python on this machine, so the block was not parsed"
  elif "$PY" -I -B -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1])' "$TMP/blocks/$1.txt" < /dev/null > "$TMP/py.log" 2>&1; then
    report PASS "parses as Python"
  else
    report FAIL "does not parse as Python: $(tail -n 1 "$TMP/py.log" | tr -d '\r')"
  fi
  report FAIL "no rule to run Python commands, so they were not run: add one to tests/test_readme_commands.sh"
}

# Every non-R block, in README order
echo; echo "=== Shell, PowerShell and other blocks"
while IFS=$'\t' read -r n line lang; do
  case "$lang" in
    r) ;;
    bash|sh|shell|zsh)
      while IFS=$'\t' read -r start cmd; do shell_command "$((line + start))" "$cmd"; done < <(commands_of "$TMP/blocks/$n.txt") ;;
    powershell|pwsh|ps1|ps)
      while IFS=$'\t' read -r start cmd; do ps_command "$((line + start))" "$cmd"; done < <(commands_of "$TMP/blocks/$n.txt") ;;
    python|py|python3) py_block "$n" "$line" ;;
    text|txt|output|xml|json|yaml|yml|csv|tsv|md|markdown|mermaid|html|tex|latex|diff)
      begin "$NAME:$line ($lang block)"; report NOTE "not commands, so not checked" ;;
    "") begin "$NAME:$line (block with no language)"; report FAIL "tag the block with its language (bash, r, or text if it holds no commands)" ;;
    "(unclosed)") begin "$NAME:$line"; report FAIL "a fenced block is never closed" ;;
    *) begin "$NAME:$line ($lang block)"; report FAIL "no rule for $lang blocks: add one to tests/test_readme_commands.sh" ;;
  esac
done < "$TMP/blocks/index.tsv"

# 6. Summary ####
echo
echo "=== summary: $NPASS passed, $NFAIL failed, $NSKIP skipped with a reason ($((SECONDS - T0)) s)"
for f in ${FAILED[@]+"${FAILED[@]}"}; do echo "FAIL  $f"; done
if [ "$NFAIL" = 0 ]; then echo "PASS: every command in $NAME ran clean or was skipped with a reason"; exit 0; fi
echo "FAIL: $NFAIL check(s) failed"
exit 1
