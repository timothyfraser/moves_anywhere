# Run manifest: the one file that means "this run finished"

Every MOVES ANYWHERE run ends by writing `run_manifest.json`, a small JSON file (about 5 KB)
that says whether the run succeeded, why it stopped if it did not, and exactly what went in
and came out: the image and MOVES version, the runspec settings, a SHA-256 checksum and size
for every input and output, how long each stage took, and the machine it ran on.

It is written **last**, after every other output is stored, so its presence is the single
signal that a run is over, in every I/O mode. That replaces checking for `data.csv`, which
never worked for rate-mode runs (they produce no `data.csv`) and could not tell a failed run
from one still running. A platform that orders runs only has to watch for this one file.

The manifest also makes a run auditable later: anyone holding the outputs can check them
against the recorded checksums and see which MOVES build produced them. How the files arrive
and leave is described in [`RUN_TICKET.md`](RUN_TICKET.md); the scripts that produce them are
listed in [`README_scripts.md`](README_scripts.md).

---

## For agents

Normative. The pack step (`scripts/task_pack.sh`, after `task_summarize.R`) writes
`run_manifest.json`; the push step stores it last ([`RUN_TICKET.md`](RUN_TICKET.md) §4).

### 1. Rules

- **Written last, always.** In `mounted` mode it is written to `/cat/inputs/` after the other
  pack outputs; in `ticket` and `sync` mode it is PUT after every other output PUT has
  finished. A failed run writes one too, with `status: failed`. Its presence is the
  completion signal in every mode; no other file is.
- **Assembled after the outcome is known.** In ticket and sync mode the push of the other
  outputs happens first, so `status` and `outputs` describe what was actually stored.
- The manifest does not list itself in `outputs` and carries no checksum of itself.
- No secret goes in the manifest: no URL, no token, no environment dump.
- `stop_reason` is at most 110 characters (the platform stores it in a 110-character field),
  plain ASCII, one line. It is truncated, never rejected.
- Times are UTC RFC 3339 with a `Z` suffix; durations are whole seconds.
- Serialise with `python3 -I -c` and `json.dump(..., indent=2, sort_keys=True)`.

### 2. What the platform reads

| Field | Read by the platform for | Effect |
|---|---|---|
| `manifest_version` | parsing | unknown major version: the run is marked failed, `manifest unreadable` |
| `run_id` | matching | must equal the run it was written for; otherwise ignored and logged |
| `status` | the order status | `ok` → done; `failed` → failed |
| `stop_reason` | the order message | shown as `failed: <stop_reason>` (truncated to fit 110 characters) |
| `outputs[name = data.csv.gz]` (inventory) or the `rateper*.csv.gz` set (rate) | result availability | `status: ok` with the result object missing from `outputs`, or missing from the store, is treated as failed: `manifest ok but result missing` |

Everything else (`mode`, `image`, `moves`, `runspec`, `inputs`, the rest of `outputs`,
`timings`, `started_at`, `finished_at`, `host`) is informational: kept for audit, support,
cost estimates and reproduction, and never used to decide status.

### 3. Fields

| Field | Type | Source |
|---|---|---|
| `manifest_version` | integer, `1` | constant |
| `run_id` | string or null | ticket `run_id`; else `RUN_ID`; else null |
| `status` | `ok` \| `failed` | pipeline exit status and push results ([`RUN_TICKET.md`](RUN_TICKET.md) §4.3) |
| `stop_reason` | string, ≤ 110 | `MOVES finished` when ok; otherwise the first failure, e.g. `MOVES exited 1: see moveslog.txt.gz`, `input fetch failed: vmt.csv HTTP 404`, `push failed: data.csv.gz HTTP 403` |
| `mode` | `inv` \| `rate` | `parameters.json` `mode` (`inv` → `inv`, `rates` → `rate`) |
| `image` | {`name`, `digest`} | `MOVES_IMAGE`, `MOVES_IMAGE_DIGEST` set by the runner; null members when unset |
| `moves` | {`commit`, `default_db`} | `MOVES_COMMIT` baked into the image at build; the default database name from MOVES's configuration file |
| `runspec` | object or null | from `parameters.json`: `geoid`, `year`, `mode`, `geoaggregation`, `timeaggregation`, `pollutants` (its `pollutant` array), and the effective `debug` ([`RUN_TICKET.md`](RUN_TICKET.md) §1) |
| `inputs` | [{`name`, `bytes`, `sha256`}] | every file in `/cat/inputs` after fetch and before `task_adapt.R`, sorted by name (the user's files; not the adapted `_*.csv`) |
| `outputs` | [{`name`, `bytes`, `sha256`}] | each output stored (ticket and sync) or written (mounted), sorted by name, excluding the manifest |
| `timings` | {stage: seconds} | `date +%s` around each stage; a stage that did not run is absent |
| `started_at`, `finished_at` | date-time | start of the first stage; moment the manifest is assembled |
| `host` | {`cpus`, `mem_bytes`} | `nproc`; the container memory limit from `/sys/fs/cgroup/memory.max` when it is a number, else `MemTotal` from `/proc/meminfo` × 1024 |

Timing stage keys, in run order: `fetch` (ticket and sync mode only), `check_inputs`,
`adapt`, `db_create`, `importer`, `moves`, `postprocess`, `pack`, `push`. `push` covers the
PUTs before the manifest; the manifest's own PUT cannot be timed inside it.

### 4. JSON Schema (draft-07)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "run_manifest.schema.json",
  "title": "MOVES ANYWHERE run manifest",
  "type": "object",
  "required": ["manifest_version", "run_id", "status", "stop_reason", "mode", "image", "moves",
               "runspec", "inputs", "outputs", "timings", "started_at", "finished_at", "host"],
  "additionalProperties": false,
  "definitions": {
    "file": {
      "type": "object",
      "required": ["name", "bytes", "sha256"],
      "additionalProperties": false,
      "properties": {
        "name": { "type": "string", "pattern": "^[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$" },
        "bytes": { "type": "integer", "minimum": 0 },
        "sha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" }
      }
    }
  },
  "properties": {
    "manifest_version": { "type": "integer", "const": 1 },
    "run_id": { "type": ["string", "null"], "pattern": "^d[0-9]{2,5}-u[0-9]+-o[0-9]+$" },
    "status": { "type": "string", "enum": ["ok", "failed"] },
    "stop_reason": { "type": "string", "minLength": 1, "maxLength": 110 },
    "mode": { "type": "string", "enum": ["inv", "rate"] },
    "image": {
      "type": "object",
      "required": ["name", "digest"],
      "additionalProperties": false,
      "properties": {
        "name": { "type": ["string", "null"] },
        "digest": { "type": ["string", "null"], "pattern": "^sha256:[0-9a-f]{64}$" }
      }
    },
    "moves": {
      "type": "object",
      "required": ["commit", "default_db"],
      "additionalProperties": false,
      "properties": {
        "commit": { "type": ["string", "null"], "pattern": "^[0-9a-f]{7,40}$" },
        "default_db": { "type": ["string", "null"] }
      }
    },
    "runspec": {
      "type": ["object", "null"],
      "required": ["geoid", "year", "mode", "geoaggregation", "timeaggregation", "pollutants", "debug"],
      "additionalProperties": false,
      "properties": {
        "geoid": { "type": "string", "pattern": "^[0-9]{2,5}$" },
        "year": { "type": "integer", "minimum": 1990, "maximum": 2060 },
        "mode": { "type": "string" },
        "geoaggregation": { "type": "string" },
        "timeaggregation": { "type": "string" },
        "pollutants": { "type": "array", "items": { "type": "integer" } },
        "debug": { "type": "boolean" }
      }
    },
    "inputs": { "type": "array", "items": { "$ref": "#/definitions/file" } },
    "outputs": { "type": "array", "items": { "$ref": "#/definitions/file" } },
    "timings": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "fetch": { "type": "integer", "minimum": 0 },
        "check_inputs": { "type": "integer", "minimum": 0 },
        "adapt": { "type": "integer", "minimum": 0 },
        "db_create": { "type": "integer", "minimum": 0 },
        "importer": { "type": "integer", "minimum": 0 },
        "moves": { "type": "integer", "minimum": 0 },
        "postprocess": { "type": "integer", "minimum": 0 },
        "pack": { "type": "integer", "minimum": 0 },
        "push": { "type": "integer", "minimum": 0 }
      }
    },
    "started_at": { "type": "string", "format": "date-time" },
    "finished_at": { "type": "string", "format": "date-time" },
    "host": {
      "type": "object",
      "required": ["cpus", "mem_bytes"],
      "additionalProperties": false,
      "properties": {
        "cpus": { "type": "integer", "minimum": 1 },
        "mem_bytes": { "type": "integer", "minimum": 0 }
      }
    }
  }
}
```

`runspec` is `null` when `parameters.json` was never fetched or cannot be parsed; that only
happens on a `failed` run, and consumers never read `runspec` on a failed run.

### 5. Example (inventory run, ok)

Checksums below are illustrative, not from a real run.

```json
{
  "finished_at": "2026-11-02T19:47:31Z",
  "host": { "cpus": 1, "mem_bytes": 4294967296 },
  "image": {
    "digest": "sha256:4b1f0c6a2e9d8b7c5a3f1e0d9c8b7a6f5e4d3c2b1a0f9e8d7c6b5a4f3e2d1c0b",
    "name": "moves-anywhere:v3"
  },
  "inputs": [
    { "bytes": 1342, "name": "parameters.json", "sha256": "0a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f9" },
    { "bytes": 10240, "name": "rs_custom.xml", "sha256": "1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90a" },
    { "bytes": 5832, "name": "vmt.csv", "sha256": "2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90a1b" }
  ],
  "manifest_version": 1,
  "mode": "inv",
  "moves": { "commit": "3e5a7c9", "default_db": "movesdb20241112" },
  "outputs": [
    { "bytes": 406859, "name": "data.csv.gz", "sha256": "3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c" },
    { "bytes": 20480, "name": "moveslog.txt.gz", "sha256": "4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d" },
    { "bytes": 6377932, "name": "replication.tar.xz", "sha256": "5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e" }
  ],
  "run_id": "d36109-u1-o1",
  "runspec": {
    "debug": false,
    "geoaggregation": "county",
    "geoid": "36109",
    "mode": "inv",
    "pollutants": [90, 98, 2, 118, 112, 119, 5, 33, 32, 6, 3, 100, 110, 106, 107, 116, 117, 115, 31, 91, 1],
    "timeaggregation": "year",
    "year": 2022
  },
  "started_at": "2026-11-02T19:16:02Z",
  "status": "ok",
  "stop_reason": "MOVES finished",
  "timings": {
    "adapt": 41,
    "check_inputs": 0,
    "db_create": 12,
    "fetch": 3,
    "importer": 95,
    "moves": 1544,
    "pack": 14,
    "postprocess": 63,
    "push": 6
  }
}
```

A failed run differs in `status: "failed"`, a `stop_reason` such as
`"MOVES exited 1: see moveslog.txt.gz"`, an `outputs` list holding only what was stored
(typically `moveslog.txt.gz` and `replication.tar.xz`), and `timings` without the stages that
never ran.
