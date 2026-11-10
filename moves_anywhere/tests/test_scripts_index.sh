#!/bin/bash
# test_scripts_index.sh #######################################################
#
# What:      tests/test_scripts_index.sh: proves docs/README_scripts.md is current.
# Does:      Regenerates the scripts guide to a temporary file and compares it with the committed one.
# Called by: Developer tool: test of the scripts guide. Not run by launch.sh.
# Reads:     moves_anywhere/scripts/ headers (through dev/make_scripts_index.R), docs/README_scripts.md
# Writes:    a temporary file, removed on exit
# Exits:     0 if the committed guide matches; 1 if it differs (re-run dev/make_scripts_index.R)
###############################################################################

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here/../.." || exit 1
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
Rscript moves_anywhere/dev/make_scripts_index.R --out "$tmp" > /dev/null || { echo "FAIL: generator error"; exit 1; }
if diff -q "$tmp" docs/README_scripts.md > /dev/null; then
  echo "PASS: docs/README_scripts.md matches the script headers"
else
  echo "FAIL: docs/README_scripts.md is stale: run Rscript moves_anywhere/dev/make_scripts_index.R"
  exit 1
fi
