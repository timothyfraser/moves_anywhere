# Changelog

## 3.0.0

Image `tmf77/moves-anywhere:v3` (also `v3.0.0`). `v2` is unchanged and stays available.

### What changed since v2

- **Slimmer, pinned image.** EPA MOVES is pinned to one commit (`MOVES_COMMIT`, fetched once, shallow) and compiled at build time, not on every run. The MOVES tree and the default database are written in one layer. The image drops gcloud and gcsfuse (about 9.16 GB to 4.12 GB locally). Package versions are listed in [`docs/PINS_v3.md`](docs/PINS_v3.md). (#4)
- **Ticket mode.** A run can take its inputs from and send its outputs to a ticket, described in [`docs/RUN_TICKET.md`](docs/RUN_TICKET.md). (#3, #5)
- **Run manifest.** Every run ends by writing `run_manifest.json`, the one file that says the run is over, whether it succeeded, and a checksum for every input and output. Described in [`docs/RUN_MANIFEST.md`](docs/RUN_MANIFEST.md). (#3, #5)
- **Replication kit.** A run can pack its inputs, settings and outputs into a kit; see [`docs/REPLICATION_KIT.md`](docs/REPLICATION_KIT.md). (#5)
- **Runtime debug switch.** MOVES debug data is switched on with `"debug": true` in `parameters.json`, not at build time. (#4)
- **`run.sh` and `run.ps1`.** One command runs a local folder of inputs, and the script exits `0` only when the run produced results. Both now default to the `v3` image. (#7)
- **Failed runs say so.** A run with no results reports `failed` (#6). A failed R step or adapter stops the run with that step's exit status and a `stop_reason`, and the adapt step names the table that failed (#12).
- **`compare_outputs.py`.** An exact per-key comparison of two MOVES output folders, used to check that a run matches a reference run. (#2)
- **Apache License 2.0.** The repository was relicensed from GPL-3.0. (#1)
- **Documentation.** The README has the new look and the published citation, and its repository links and `catr` install commands are fixed (#8, #9). Every script carries one standard header, and `CONTRIBUTING.md` describes it (#10). The guides were corrected (#11), the scripts guide is generated from the headers (#13), and the guides have an index, top and tail links and a `CITATION.cff` (#14). A test runs every command in the README (#15).

### Known limits

- The image is built for `linux/amd64` (Intel/AMD). It has not been tested on Apple-silicon Macs.
- `catr` 0.2.0 still imports the Google R packages (`gargle`, `googleAuthR`, `googleCloudStorageR`), so they stay in the image at their v2 versions. No Google service is needed to run.

### Rollback

Set `MOVES_IMAGE=tmf77/moves-anywhere:v2` (or pass `--image`) to run the previous image. `v2` is not modified by this release.

### Failure handling, detail

- A failed R step in `launch.sh` (check packages, adapt, create database, create importer, postprocess, summarize) now stops the run with that step's exit status and a `stop_reason`, instead of limping on.
- `task_adapt.R` names the adapter that failed: `adapt failed on <table>: <first error line>`. New ticket-mode test: `moves_anywhere/tests/test_bad_table.sh`.
- In mounted mode a failed step exits non-zero and prints the reason to the log, and no manifest is written; in ticket mode the failed manifest carries the reason.
