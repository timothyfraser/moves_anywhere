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
# Adapt always runs before MOVES: the fallback must not point to a moveslog that was never made
fb <- adapt_reason(simpleError(""))
stopifnot(fb == "failed before MOVES started; there is no MOVES log", !grepl("moveslog", fb))
stopifnot(nchar(paste0("adapt failed on ", "offnetwork", ": ", fb)) <= 110)
cat("PASS: test_adapt_errors.R
")
