# test_adapt_errors.R: offline check that the adapter error handler can always read an error (2026-11-19: a malformed
# condition crashed run_adapter's handler on Cloud MOVES and the real cause was lost). Run from the repository root.
# Exits 0 and prints PASS, or stops.
src <- readLines("moves_anywhere/scripts/task_adapt.R")
i <- grep("^adapt_first_line = function", src); j <- grep("^run_adapter = function", src) - 1
eval(parse(text = src[i:j]))
bad <- structure(class = c("weird", "error", "condition"), list())
stopifnot(nzchar(adapt_safe_message(bad)))
stopifnot(adapt_safe_message(simpleError("boom")) == "boom")
stopifnot(adapt_reason(simpleError("first line\nsecond")) == "first line")
cat("PASS: test_adapt_errors.R
")
