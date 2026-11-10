# Changelog

## Unreleased

- A failed R step in `launch.sh` (check packages, adapt, create database, create importer, postprocess, summarize) now stops the run with that step's exit status and a `stop_reason`, instead of limping on.
- `task_adapt.R` names the adapter that failed: `adapt failed on <table>: <first error line>`. New ticket-mode test: `moves_anywhere/tests/test_bad_table.sh`.
- In mounted mode a failed step exits non-zero and prints the reason to the log, and no manifest is written; in ticket mode the failed manifest carries the reason.
