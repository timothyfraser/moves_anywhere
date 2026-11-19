# test_adapt_connections.R: offline check that get_table() (scripts/adapt_functions.R) closes its database connection
# whether the query succeeds or fails (PS-21, 2026-11-19: a connection left to the garbage collector printed
# "call dbDisconnect() when finished working with a connection" just before an adapter failure).
# No MariaDB, no Docker: catr, DBI, dplyr and setwd are replaced by stubs that record what happened.
# Run from the repository root. Exits 0 and prints PASS, or stops.
src = readLines("moves_anywhere/scripts/adapt_functions.R")
i = grep("^get_table = function", src)
j = grep("^#' @name get_is_custom", src) - 1

# Stub world: one fake connection whose state we can read afterwards
state = new.env()
reset = function(fail){ state$open = 0L; state$closed = 0L; state$fail = fail }
stubs = list(
  catr = list(
    translate_rs = function(.runspec){ list(defaultdbname = "movesdb_fake") },
    connect = function(type, dbname){ state$open = state$open + 1L; structure(list(db = dbname), class = "fakecon") }
  ),
  DBI = list(dbDisconnect = function(conn){ state$closed = state$closed + 1L; invisible(TRUE) })
)
env = new.env()
env$`::` = function(pkg, name){ stubs[[deparse(substitute(pkg))]][[deparse(substitute(name))]] }
env$library = function(...){ invisible(NULL) }
env$setwd = function(dir){ invisible(getwd()) }
env$`%>%` = magrittr::`%>%`
env$tbl = function(con, tablename){ if(state$fail){ stop("Table 'movesdb_fake.", tablename, "' doesn't exist") }; data.frame(x = 1:3) }
env$collect = function(x){ x }
env$dbDisconnect = env$`::`(DBI, dbDisconnect)
eval(parse(text = src[i:j]), envir = env)

# 1. Success: data comes back and the connection is closed once
reset(fail = FALSE)
out = env$get_table("sourcetypeage")
stopifnot(nrow(out) == 3, state$open == 1L, state$closed == 1L)

# 2. Error between open and close: the error still reaches the caller and the connection is closed once
reset(fail = TRUE)
err = tryCatch(env$get_table("nosuchtable"), error = function(e) conditionMessage(e))
stopifnot(grepl("doesn't exist", err), state$open == 1L, state$closed == 1L)

# 3. The helper closes with on.exit, so no exit path can skip it
body_text = paste(src[i:j], collapse = "\n")
stopifnot(grepl("on.exit(DBI::dbDisconnect(custom), add = TRUE)", body_text, fixed = TRUE))

cat("PASS: test_adapt_connections.R\n")
