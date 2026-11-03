# The replication kit: rerun any MOVES ANYWHERE result on a stock MOVES install

Every finished run ends with a file called `replication.tar.xz`. It holds everything needed
to get the same numbers out of EPA's own MOVES, with none of this project's software: the
runspec, the tables MOVES actually read, and the results we got. If you do not trust the
cloud, or a reviewer wants proof, or you want to change one input and rerun by hand, this is
the file to start from. A typical kit is about 6 MB.

To check a result, you rebuild the MOVES input database from the kit, run the runspec in
MOVES, and compare your `movesoutput` table with the `movesoutput.csv` in the kit. The match
is exact: for every combination of pollutant, process, vehicle type, month, fuel, road type,
regulatory class and model year, the sum of `emissionQuant` must be identical. MOVES is
deterministic, so a different number means a different MOVES build or a different default
database, not noise.

## Reproduce a run on Windows, step by step

You need a stock MOVES 5 install (the version in the runspec header, `MOVES5.0.0`, with the
default database `movesdb20241112`) and its MariaDB/MySQL server running.

1. **Unpack the kit** into an empty folder, for example `C:\kit`. Windows 11 unpacks `.tar.xz`
   with `tar -xJf replication.tar.xz` in a terminal; 7-Zip also works (unpack twice: `.xz`
   gives a `.tar`, then the `.tar`).
2. **Create the input database.** In the MySQL client that ships with MOVES, run
   `CREATE DATABASE IF NOT EXISTS custom;`. The name `custom` matters: the runspec points at it.
3. **Point the importer at your folder.** `kit\importer.xml` lists the tables to load with
   relative paths (`./_avft.csv`). MOVES resolves them from its own folder, so rewrite them
   once as absolute paths. In Git Bash from `C:\kit`:
   `sed "s|<filename>\./|<filename>$(pwd)/|" kit/importer.xml > importer_abs.xml`.
   Or open `kit\importer.xml` in a text editor and replace `./` with `C:/kit/`.
4. **Import the tables.** From the MOVES folder: `ant dbimporter -Dimport="C:/kit/importer_abs.xml"`.
   Afterwards `custom` holds the adapted tables (every `_*.csv` in the kit).
5. **Run MOVES.** Either open `rs_custom.xml` in the MOVES GUI and press Run, or from the MOVES
   folder: `ant run -Drunspec="C:/kit/rs_custom.xml"`. The runspec reads `custom` and writes
   to the output database `moves`.
6. **Export and compare.** Export the `movesoutput` and `movesactivityoutput` tables from the
   `moves` database to CSV, with the same column names, then compare with the copies in the kit
   using `scripts/compare_outputs.py` from the moves_anywhere repository:
   `python scripts/compare_outputs.py C:\kit C:\your_export`. Every line should say `PASS`.

If you only want to inspect, skip steps 2 to 6: the `_*.csv` tables are plain CSV, and
`movesoutput.csv` is the answer.

## What is in the kit

| File | What it is |
|---|---|
| `rs_custom.xml` | The MOVES runspec: place, year, pollutants, aggregation. Open it in the MOVES GUI. |
| `parameters.json` | The order's settings (geoid, year, pollutants, mode, aggregation). |
| user tables, e.g. `vmt.csv` | The tables the user supplied, as supplied. Empty if the run used defaults only. |
| `_*.csv` | The adapted tables: exactly what was loaded into MOVES (users' tables merged with defaults). |
| `movesoutput.csv`, `movesactivityoutput.csv` | MOVES's raw results for this run: the reference you compare against. |
| `diagnostics.txt` | A short summary of the run's headline numbers, when present. |
| `moveslog.txt` | The MOVES log, when present. |
| `kit/importer.xml` | The importer used to load the `_*.csv` tables, with relative paths. |
| `kit/README.txt` | A one-page version of the steps above. |

Not in the kit: `data.csv.gz` (the post-processed result, delivered next to the kit),
`moveslog.txt.gz`, and `run_manifest.json`. The manifest records the checksum of the kit and
of every input and output, so you can check that the kit you hold is the one the run produced
([`RUN_MANIFEST.md`](../../docs/RUN_MANIFEST.md)).

---

## For agents

Implementation: `moves_anywhere/scripts/task_pack.sh` (sourced by the launcher after the
outputs are compressed), `moves_anywhere/scripts/manifest_fields.py` (stdlib helper that
assembles the manifest), proven by `moves_anywhere/tests/test_pack.sh`. Output contract:
[`RUN_TICKET.md`](../../docs/RUN_TICKET.md) §2 (the object set) and [`RUN_MANIFEST.md`](../../docs/RUN_MANIFEST.md).

### Kit contents (normative)

Built in `$INPUTS_DIR` (default `/cat/inputs`), flat at the top level plus a `kit/` folder:

1. `rs_custom.xml`, `parameters.json`, if present.
2. Every `*.csv` with no leading underscore, except the pipeline's own files: `data.csv`,
   `movesoutput.csv`, `movesactivityoutput.csv`, and the uncompressed rate outputs
   (`rateperhour.csv`, `ratepervehicle.csv`, `rateperdistance.csv`, `rateperstart.csv`,
   `startspervehicle.csv`, `rateperprofile.csv`, `movesrun.csv`).
3. Every adapted `_*.csv`.
4. `movesoutput.csv`, `movesactivityoutput.csv`, `diagnostics.txt`, `moveslog.txt`, each
   only if present.
5. `kit/importer.xml`: `importer.xml` with `/cat/inputs/` rewritten to `./` (only if
   `importer.xml` exists), and `kit/README.txt`.

Excluded: `data.csv`, `data.csv.gz`, `moveslog.txt.gz`, `run_manifest.json`, `.timings`,
`*.part`, and the kit itself. Only files already present are added; a missing optional file
never fails the step. A missing `moveslog.txt` (only the `.gz` exists) is not regenerated.

Determinism: the member list is sorted (`LC_ALL=C sort`), passed with `tar -T --no-recursion`,
with `--mtime=@0 --owner=0 --group=0 --numeric-owner --mode='u=rw,go=r'`, then `xz -6 -T0`.
Two runs on the same folder give the same SHA-256. Across hosts the bytes can differ only if
`xz` runs single-threaded on one host and multi-threaded on another (the block layout
differs; the content does not), so compare members, not the archive hash, across machines.
The archive is written as `replication.tar.xz.part` and renamed, so a crash never leaves a
truncated kit.

### Manifest assembly

`task_pack.sh` writes `run_manifest.json` in `$INPUTS_DIR` right after the kit. `inputs` are
`rs_custom.xml`, `parameters.json` and the user CSVs (not `_*.csv`); `outputs` are those of
`data.csv.gz`, the seven rate `*.csv.gz` objects, `moveslog.txt.gz` and `replication.tar.xz`
that exist; the manifest does not list itself. Settings come from `parameters.json` (its
`pollutant` array becomes `runspec.pollutants`); `mode` `rates` becomes `rate`. Environment:
`RUN_ID`, `MOVES_IMAGE`, `MOVES_IMAGE_DIGEST`, `MOVES_COMMIT` (a git checkout at
`MOVES_DIR`, default `/cat/EPA_MOVES_Model`, wins over the variable), `MOVES_DEFAULT_DB`
(default `movesdb20241112`), `MOVES_DEBUG`, `RUN_STATUS` (default `ok`), `RUN_STOP_REASON`,
`RUN_STARTED_AT`, `RUN_FINISHED_AT`. Stage seconds come from `$INPUTS_DIR/.timings`
(`stage seconds` per line; an absent stage is omitted); `pack` defaults to the step's own
duration. Without `RUN_STARTED_AT`, `started_at` is `finished_at` minus the recorded
timings. The manifest is validated with `jsonschema` against the schema block in
`RUN_MANIFEST.md` when both are available, else with structural checks; an invalid manifest is
still written and the step returns 1. If the kit cannot be built, an otherwise `ok` run is
recorded as `failed` with `stop_reason` `replication kit could not be built`.

### Tolerance

Exact. `scripts/compare_outputs.py <kit-folder> <your-folder>` groups `movesoutput.csv` by
`pollutantID, processID, sourceTypeID, monthID, fuelTypeID, roadTypeID, regClassID,
modelYearID` and `movesactivityoutput.csv` by `activityTypeID, sourceTypeID, monthID,
fuelTypeID, roadTypeID, regClassID, modelYearID`; summed metrics must be bit-identical.
Run-metadata columns (`MOVESRunID`, timestamps) are ignored. There is no tolerance band:
a mismatch means a different MOVES commit or default database. Record both from the
manifest's `moves` block before debugging anything else.

### Known limits

- Relative importer paths are resolved by MOVES against its own working folder, so the README
  tells users to rewrite them to an absolute path; `kit/importer.xml` is not directly runnable
  from an arbitrary folder.
- The kit holds one run. Rate-mode runs include whichever of `movesoutput.csv` and
  `movesactivityoutput.csv` exist; the rate result objects stay outside the kit.
