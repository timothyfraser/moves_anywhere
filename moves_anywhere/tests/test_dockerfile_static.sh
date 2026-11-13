#!/bin/bash
# test_dockerfile_static.sh ###################################################
#
# What:      Static checks on moves_anywhere/Dockerfile (no docker needed): the ~1 GB MOVES tree is
#            written in ONE layer and the database dump never survives in an image layer.
# Does:      Joins backslash continuations, greps the instructions, prints PASS or FAIL per assertion.
# Called by: Developer tool: test of the Dockerfile. Not run by launch.sh.
# Reads:     moves_anywhere/Dockerfile
# Writes:    nothing (stdout only)
# Exits:     0 if every assertion passes; otherwise the number of failed assertions
# Usage: bash moves_anywhere/tests/test_dockerfile_static.sh
###############################################################################

D="$(cd "$(dirname "$0")/.." && pwd)/Dockerfile"
FAILS=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILS=$((FAILS + 1)); fi; }

# Join backslash continuations so each Dockerfile instruction is one line.
INS=$(sed 's/\r$//' "$D" | sed -e ':a' -e '/\$/N; s/\\n//; ta')
big=$(printf '%s\n' "$INS" | grep -E '^RUN .*setupdb\.sh' | grep -v 'chmod \+x /cat/scripts')
nbig=$(printf '%s\n' "$big" | grep -c .)

check "exactly one RUN runs setupdb.sh" '[ "$nbig" = 1 ]'
check "git clone is gone" '! printf "%s\n" "$INS" | grep -q "git clone"'
check "one shallow fetch of MOVES_COMMIT, in the combined RUN" 'printf "%s\n" "$big" | grep -q "git fetch.*--depth 1 origin .*MOVES_COMMIT"'
check ".git is deleted in the combined RUN" 'printf "%s\n" "$big" | grep -q "rm -rf .git"'
check "chown -R occurs only in the combined RUN" '[ "$(printf "%s\n" "$INS" | grep -c "chown -R")" = 1 ] && printf "%s\n" "$big" | grep -q "chown -R"'
check "chmod -R occurs only in the combined RUN" '[ "$(printf "%s\n" "$INS" | grep -c "chmod -R")" = 1 ] && printf "%s\n" "$big" | grep -q "chmod -R"'
check "unzip happens in the combined RUN" '[ "$(printf "%s\n" "$INS" | grep -c "unzip -")" = 1 ] && printf "%s\n" "$big" | grep -q "unzip "'
check "the .sql is deleted in the same RUN that loads it" 'printf "%s\n" "$big" | grep -Eq "setupdb\.sh.*rm -f .*movesdb20241112\.sql"'
check "the .zip is deleted in the same RUN" 'printf "%s\n" "$big" | grep -Eq "rm -f .*movesdb20241112\.zip"'
check "setenv.sh, my.cnf, setupdb.sh are COPYed before the combined RUN" '
  l_run=$(printf "%s\n" "$INS" | grep -nE "^RUN .*setupdb\.sh" | grep -v "scripts" | head -1 | cut -d: -f1)
  for f in setenv.sh my.cnf setupdb.sh; do l=$(printf "%s\n" "$INS" | grep -n "^COPY $f" | head -1 | cut -d: -f1); [ -n "$l" ] && [ "$l" -lt "$l_run" ] || exit 1; done'
check "MOVES_COMMIT is exported as ENV" 'printf "%s\n" "$INS" | grep -q "^ENV MOVES_COMMIT="'
check "no gcsfuse" '! grep -qi "gcsfuse" "$D"'
check "no google-cloud-cli" '! grep -qi "google-cloud-cli" "$D"'
check "compile RUN kept" 'printf "%s\n" "$INS" | grep -q "ant compileall"'
check "debug property kept" 'grep -q "moves.keepDebugData" "$D"'
check "release labels present" 'grep -q "^LABEL version=\"3\.0\.0\"" "$D" && grep -q "org.opencontainers.image.source=\"https://github.com/timothyfraser/moves_anywhere\"" "$D" && grep -q "org.opencontainers.image.revision=" "$D" && grep -q "org.opencontainers.image.licenses=\"Apache-2.0\"" "$D"'
check "no development labels" '! grep -qiE "status=\"development\"|UNDER DEVELOPMENT|3\.0-dev" "$D"'

echo
if [ "$FAILS" = 0 ]; then echo "PASS: all assertions"; else echo "FAIL: $FAILS assertion(s)"; fi
exit "$FAILS"
