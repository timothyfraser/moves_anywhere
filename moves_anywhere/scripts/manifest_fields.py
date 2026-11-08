#!/usr/bin/env python3
# manifest_fields.py ##########################################################
#
# What:      Assemble run_manifest.json (docs/RUN_MANIFEST.md) from arguments and small files.
# Does:      Builds the manifest so that bash never builds JSON by hand, writes it, then
#            validates it. Standard library only.
# Called by: task_pack.sh, step 15 of launch.sh
# Reads:     --inputs-tsv, --outputs-tsv, --timings, --parameters, --runspec, --schema-from
#            (each only if given); /sys/fs/cgroup/memory.max or /proc/meminfo for host info
# Writes:    --out (run_manifest.json, via <out>.part); problems to stderr
# Exits:     0 if the manifest is valid; 1 if validation fails (the manifest is still written);
#            2 on a usage error (argparse)
###############################################################################
"""Assemble run_manifest.json (docs/RUN_MANIFEST.md) from arguments and small files.

Used by scripts/task_pack.sh so that bash never builds JSON by hand. Standard library only.

Usage (all values are plain strings; an empty string means "not set" and becomes null):
    manifest_fields.py --out run_manifest.json \
        --inputs-tsv inputs.tsv --outputs-tsv outputs.tsv \
        [--timings .timings] [--parameters parameters.json] [--runspec rs_custom.xml] \
        [--run-id ID] [--status ok|failed] [--stop-reason TEXT] \
        [--image-name N] [--image-digest sha256:...] [--moves-commit HEX] [--default-db NAME] \
        [--debug 0|1] [--started-at RFC3339Z] [--finished-at RFC3339Z] [--pack-seconds N] \
        [--schema-from docs/RUN_MANIFEST.md]

The two TSV files hold one "name<TAB>bytes<TAB>sha256" line per file.
The manifest is written even if validation fails; the exit status is then 1 and the
problems are printed to stderr. Exit 0 means the manifest is valid.
"""
import argparse
import datetime
import json
import os
import re
import sys

STAGES = ["fetch", "check_inputs", "adapt", "db_create", "importer", "moves",
          "postprocess", "pack", "push"]
RFC3339Z = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")


def nz(value):
    """Empty string / None -> None."""
    return value if value not in (None, "") else None


def read_tsv(path):
    rows = []
    if path and os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line:
                    continue
                name, nbytes, sha = line.split("\t")
                rows.append({"name": name, "bytes": int(nbytes), "sha256": sha})
    return sorted(rows, key=lambda r: r["name"])


def read_timings(path):
    out = {}
    if path and os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                parts = line.split()
                if len(parts) == 2 and parts[0] in STAGES and re.fullmatch(r"\d+", parts[1]):
                    out[parts[0]] = int(parts[1])  # last line for a stage wins
    return out


def read_json(path):
    if path and os.path.isfile(path):
        try:
            with open(path, encoding="utf-8") as fh:
                obj = json.load(fh)
            return obj if isinstance(obj, dict) else None
        except (OSError, ValueError):
            return None
    return None


def geoid_text(value):
    s = str(value).strip()
    if re.fullmatch(r"\d{3,4}", s):  # a county FIPS that lost its leading zero
        s = s.zfill(5)
    return s


def as_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return value


def build_runspec(params, debug_env):
    if params is None:
        return None
    pol = params.get("pollutant", [])
    if not isinstance(pol, list):
        pol = [pol]
    debug = bool(debug_env) or params.get("debug") is True
    return {
        "geoid": geoid_text(params.get("geoid", "")),
        "year": as_int(params.get("year")),
        "mode": str(params.get("mode", "")),
        "geoaggregation": str(params.get("geoaggregation", "")),
        "timeaggregation": str(params.get("timeaggregation", "")),
        "pollutants": [as_int(p) for p in pol],
        "debug": debug,
    }


def pick_mode(params, runspec_path, outputs):
    raw = (params or {}).get("mode")
    if raw in ("inv", "rate", "rates"):
        return "rate" if raw in ("rate", "rates") else "inv"
    if runspec_path and os.path.isfile(runspec_path):
        try:
            with open(runspec_path, encoding="utf-8", errors="replace") as fh:
                m = re.search(r'<modelscale\s+value="(\w+)"', fh.read())
            if m:
                return "rate" if m.group(1).lower() == "rates" else "inv"
        except OSError:
            pass
    if any(o["name"].startswith("rateper") for o in outputs):
        return "rate"
    return "inv"


def host_info():
    try:
        cpus = len(os.sched_getaffinity(0))
    except AttributeError:
        cpus = os.cpu_count() or 1
    mem = 0
    try:
        with open("/sys/fs/cgroup/memory.max", encoding="ascii") as fh:
            txt = fh.read().strip()
        if txt.isdigit():
            mem = int(txt)
    except OSError:
        pass
    if not mem:
        try:
            with open("/proc/meminfo", encoding="ascii") as fh:
                for line in fh:
                    if line.startswith("MemTotal:"):
                        mem = int(line.split()[1]) * 1024
                        break
        except (OSError, ValueError, IndexError):
            pass
    return {"cpus": max(cpus, 1), "mem_bytes": mem}


def clean_reason(text, status):
    text = re.sub(r"\s+", " ", (text or "").encode("ascii", "replace").decode("ascii")).strip()
    if not text:
        text = "MOVES finished" if status == "ok" else "run failed"
    return text[:110]


def now_utc():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)


def fmt(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def load_schema(md_path):
    """First fenced json block after the heading '4. JSON Schema' in RUN_MANIFEST.md."""
    if not md_path or not os.path.isfile(md_path):
        return None
    with open(md_path, encoding="utf-8") as fh:
        text = fh.read()
    head = text.find("JSON Schema")
    m = re.search(r"```json\n(.*?)\n```", text[head:] if head >= 0 else text, re.S)
    return json.loads(m.group(1)) if m else None


def structural_problems(man):
    """Minimal checks used when jsonschema or the schema block is not available."""
    probs = []
    req = ["manifest_version", "run_id", "status", "stop_reason", "mode", "image", "moves",
           "runspec", "inputs", "outputs", "timings", "started_at", "finished_at", "host"]
    for k in req:
        if k not in man:
            probs.append("missing field: " + k)
    extra = set(man) - set(req)
    if extra:
        probs.append("unknown fields: " + ",".join(sorted(extra)))
    if man.get("manifest_version") != 1:
        probs.append("manifest_version must be 1")
    if man.get("status") not in ("ok", "failed"):
        probs.append("status must be ok|failed")
    sr = man.get("stop_reason")
    if not isinstance(sr, str) or not 1 <= len(sr) <= 110:
        probs.append("stop_reason must be 1..110 characters")
    if man.get("mode") not in ("inv", "rate"):
        probs.append("mode must be inv|rate")
    for key in ("inputs", "outputs"):
        for f in man.get(key, []):
            if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9._-]{0,99}", str(f.get("name", ""))):
                probs.append("%s: bad name %r" % (key, f.get("name")))
            if not isinstance(f.get("bytes"), int) or f["bytes"] < 0:
                probs.append("%s: bad bytes for %s" % (key, f.get("name")))
            if not re.fullmatch(r"[0-9a-f]{64}", str(f.get("sha256", ""))):
                probs.append("%s: bad sha256 for %s" % (key, f.get("name")))
    for k in ("started_at", "finished_at"):
        if not RFC3339Z.match(str(man.get(k, ""))):
            probs.append(k + " is not RFC 3339 UTC")
    if not set(man.get("timings", {})) <= set(STAGES):
        probs.append("unknown timing stage")
    return probs


def validate(man, schema_md):
    """Return (validator_name, [problems])."""
    probs = []
    name = "structural"
    schema = None
    try:
        schema = load_schema(schema_md)
    except (ValueError, OSError):
        schema = None
    try:
        import jsonschema  # optional
        if schema is not None:
            name = "jsonschema"
            validator = jsonschema.Draft7Validator(schema)
            probs += ["%s: %s" % ("/".join(map(str, e.absolute_path)) or "(root)", e.message)
                      for e in validator.iter_errors(man)]
    except ImportError:
        pass
    # date-time format is not enforced by jsonschema without a format checker
    for k in ("started_at", "finished_at"):
        if not RFC3339Z.match(str(man.get(k, ""))):
            probs.append(k + " is not RFC 3339 UTC")
    if name == "structural":
        probs += structural_problems(man)
    return name, probs


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", required=True)
    ap.add_argument("--inputs-tsv")
    ap.add_argument("--outputs-tsv")
    ap.add_argument("--timings")
    ap.add_argument("--parameters")
    ap.add_argument("--runspec")
    ap.add_argument("--run-id", default="")
    ap.add_argument("--status", default="ok", choices=["ok", "failed"])
    ap.add_argument("--stop-reason", default="")
    ap.add_argument("--image-name", default="")
    ap.add_argument("--image-digest", default="")
    ap.add_argument("--moves-commit", default="")
    ap.add_argument("--default-db", default="")
    ap.add_argument("--debug", default="")
    ap.add_argument("--started-at", default="")
    ap.add_argument("--finished-at", default="")
    ap.add_argument("--pack-seconds", default="")
    ap.add_argument("--schema-from", default="")
    a = ap.parse_args(argv)

    inputs = read_tsv(a.inputs_tsv)
    outputs = read_tsv(a.outputs_tsv)
    timings = read_timings(a.timings)
    if "pack" not in timings and re.fullmatch(r"\d+", a.pack_seconds or ""):
        timings["pack"] = int(a.pack_seconds)
    params = read_json(a.parameters)

    finished = nz(a.finished_at) or fmt(now_utc())
    started = nz(a.started_at)
    if not started:  # not given: back-date by the stages we know about
        end = datetime.datetime.strptime(finished, "%Y-%m-%dT%H:%M:%SZ")
        started = fmt(end - datetime.timedelta(seconds=sum(timings.values())))

    manifest = {
        "manifest_version": 1,
        "run_id": nz(a.run_id),
        "status": a.status,
        "stop_reason": clean_reason(a.stop_reason, a.status),
        "mode": pick_mode(params, a.runspec, outputs),
        "image": {"name": nz(a.image_name), "digest": nz(a.image_digest)},
        "moves": {"commit": nz(a.moves_commit), "default_db": nz(a.default_db)},
        "runspec": build_runspec(params, a.debug == "1"),
        "inputs": inputs,
        "outputs": outputs,
        "timings": timings,
        "started_at": started,
        "finished_at": finished,
        "host": host_info(),
    }

    tmp = a.out + ".part"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, a.out)

    vname, probs = validate(manifest, nz(a.schema_from))
    if probs:
        for p in probs:
            sys.stderr.write("manifest invalid (%s): %s\n" % (vname, p))
        return 1
    sys.stderr.write("manifest ok (%s validation): %s\n" % (vname, os.path.basename(a.out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
