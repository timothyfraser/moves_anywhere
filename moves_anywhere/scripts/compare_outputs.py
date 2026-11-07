#!/usr/bin/env python3
# compare_outputs.py ##########################################################
#
# What:      Compare two MOVES output folders and print PASS/FAIL per file.
# Does:      Exact comparison: per-key sums of the metric columns must be bit-identical
#            (details and keys in the docstring below).
# Called by: Developer tool: exactness gate between two output folders
#            (docs/REPLICATION_KIT.md; tested by test_compare_outputs.py).
# Reads:     <dirA>/ and <dirB>/: movesoutput.csv, movesactivityoutput.csv, data.csv
# Writes:    stdout only (one line per file, or one JSON object with --json)
# Exits:     0 if no file FAILs; 1 if any file FAILs; 2 on a usage error (argparse)
###############################################################################
"""Compare two MOVES output folders and print PASS/FAIL per file.

Usage:
    compare_outputs.py <dirA> <dirB> [--files movesoutput,movesactivityoutput,data] [--json]

The comparison is exact. For each file the rows are grouped by a key, the
metric columns are summed per key (rows sorted by key first so float
addition happens in the same order on both sides), and the per-key sums
must be bit-identical. Run-metadata columns (MOVESRunID, iterationID,
timestamps, ...) are never part of the key or the metrics, so they cannot
cause a failure.

Files:
    movesoutput          key: pollutantID, processID, sourceTypeID, monthID,
                              fuelTypeID, roadTypeID, regClassID, modelYearID
                         sum: emissionQuant
    movesactivityoutput  key: activityTypeID, sourceTypeID, monthID, fuelTypeID,
                              roadTypeID, regClassID, modelYearID
                         sum: activity
    data                 key: year, geoid, pollutant, by, sourcetype, regclass,
                              fueltype, roadtype
                         sum: emissions, vmt, sourcehours, vehicles, starts,
                              idlehours, hoteld, hotelb, hotelo

A key column is used only if it appears in the header of both files.
Empty cells and NA count as 0 in sums. A file missing from both folders is
SKIP; missing from one is FAIL. Exit status is 0 iff no file FAILs.
"""
import argparse
import csv
import json
import os
import sys

SPECS = {
    "movesoutput": {
        "filename": "movesoutput.csv",
        "keys": ["pollutantID", "processID", "sourceTypeID", "monthID",
                 "fuelTypeID", "roadTypeID", "regClassID", "modelYearID"],
        "metrics": ["emissionQuant"],
    },
    "movesactivityoutput": {
        "filename": "movesactivityoutput.csv",
        "keys": ["activityTypeID", "sourceTypeID", "monthID", "fuelTypeID",
                 "roadTypeID", "regClassID", "modelYearID"],
        "metrics": ["activity"],
    },
    "data": {
        "filename": "data.csv",
        "keys": ["year", "geoid", "pollutant", "by", "sourcetype",
                 "regclass", "fueltype", "roadtype"],
        "metrics": ["emissions", "vmt", "sourcehours", "vehicles", "starts",
                    "idlehours", "hoteld", "hotelb", "hotelo"],
    },
}
SAMPLE = 10


def _num(cell):
    cell = cell.strip()
    if cell == "" or cell == "NA":
        return 0.0
    return float(cell)


def _header(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return next(csv.reader(fh), [])


def _sums(path, keys, metrics):
    """Return {key tuple: [sum per metric]} with deterministic add order."""
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        rows = []
        for row in reader:
            key = tuple(row[k] for k in keys)
            rows.append((key, tuple(_num(row[m]) for m in metrics)))
    rows.sort()
    out = {}
    for key, vals in rows:
        acc = out.get(key)
        if acc is None:
            out[key] = list(vals)
        else:
            for i, v in enumerate(vals):
                acc[i] += v
    return out


def _rel(a, b):
    if a == b:
        return 0.0
    if a == 0:
        return abs(b)
    return abs(a - b) / abs(a)


def _fmt_key(keys, key):
    return ",".join("%s=%s" % (k, v) for k, v in zip(keys, key))


def compare_file(name, dir_a, dir_b):
    spec = SPECS[name]
    pa = os.path.join(dir_a, spec["filename"])
    pb = os.path.join(dir_b, spec["filename"])
    ea, eb = os.path.isfile(pa), os.path.isfile(pb)
    res = {"file": spec["filename"], "status": None}
    if not ea and not eb:
        res["status"] = "SKIP"
        res["note"] = "missing in both folders"
        return res
    if ea != eb:
        res["status"] = "FAIL"
        res["note"] = "missing in folder %s" % ("B" if ea else "A")
        return res

    ha, hb = _header(pa), _header(pb)
    keys = [k for k in spec["keys"] if k in ha and k in hb]
    missing = [m for m in spec["metrics"] if m not in ha or m not in hb]
    if missing:
        res["status"] = "FAIL"
        res["note"] = "metric column(s) missing from a header: %s" % ",".join(missing)
        return res
    metrics = spec["metrics"]

    sa = _sums(pa, keys, metrics)
    sb = _sums(pb, keys, metrics)
    only_a = sorted(set(sa) - set(sb))
    only_b = sorted(set(sb) - set(sa))
    max_diff = 0.0
    differing = []
    for key in sorted(set(sa) & set(sb)):
        for i, m in enumerate(metrics):
            d = _rel(sa[key][i], sb[key][i])
            if d > 0.0:
                differing.append((d, key, m, sa[key][i], sb[key][i]))
            if d > max_diff:
                max_diff = d
    differing.sort(key=lambda t: -t[0])
    ok = not only_a and not only_b and max_diff == 0.0
    res.update({
        "status": "PASS" if ok else "FAIL",
        "key_columns": keys,
        "metric_columns": metrics,
        "keys_a": len(sa),
        "keys_b": len(sb),
        "only_in_a": len(only_a),
        "only_in_b": len(only_b),
        "only_in_a_sample": [_fmt_key(keys, k) for k in only_a[:SAMPLE]],
        "only_in_b_sample": [_fmt_key(keys, k) for k in only_b[:SAMPLE]],
        "max_rel_diff": max_diff,
        "differing_keys": len(differing),
        "differing_sample": [
            {"key": _fmt_key(keys, k), "column": m, "a": a, "b": b, "rel_diff": d}
            for d, k, m, a, b in differing[:SAMPLE]
        ],
    })
    return res


def _print(res):
    if "keys_a" not in res:
        note = res.get("note", "")
        print("%s  %s  (%s)" % (res["status"], res["file"], note))
        return
    print("%s  %s" % (res["status"], res["file"]))
    print("  key columns       : %s" % ",".join(res["key_columns"]))
    print("  keys A / B        : %d / %d" % (res["keys_a"], res["keys_b"]))
    print("  only in A / B     : %d / %d" % (res["only_in_a"], res["only_in_b"]))
    for label, sample, n in (("A", res["only_in_a_sample"], res["only_in_a"]),
                             ("B", res["only_in_b_sample"], res["only_in_b"])):
        for s in sample:
            print("    only in %s: %s" % (label, s))
        if n > len(sample):
            print("    ... and %d more only in %s" % (n - len(sample), label))
    print("  max rel diff      : %r" % res["max_rel_diff"])
    for d in res["differing_sample"]:
        print("    differs: %s %s a=%r b=%r rel=%r"
              % (d["key"], d["column"], d["a"], d["b"], d["rel_diff"]))
    if res["differing_keys"] > len(res["differing_sample"]):
        print("    ... and %d more differing cells"
              % (res["differing_keys"] - len(res["differing_sample"])))


def main(argv=None):
    ap = argparse.ArgumentParser(description="Exact comparison of two MOVES output folders.")
    ap.add_argument("dir_a")
    ap.add_argument("dir_b")
    ap.add_argument("--files", default=",".join(SPECS),
                    help="comma-separated subset of: %s" % ",".join(SPECS))
    ap.add_argument("--json", action="store_true", help="print one JSON object")
    args = ap.parse_args(argv)

    names = [n.strip() for n in args.files.split(",") if n.strip()]
    bad = [n for n in names if n not in SPECS]
    if bad:
        ap.error("unknown file(s): %s" % ",".join(bad))

    results = [compare_file(n, args.dir_a, args.dir_b) for n in names]
    failed = any(r["status"] == "FAIL" for r in results)
    overall = "FAIL" if failed else "PASS"
    if args.json:
        print(json.dumps({"dir_a": args.dir_a, "dir_b": args.dir_b,
                          "overall": overall, "files": results}, indent=2))
    else:
        for r in results:
            _print(r)
        print("OVERALL: %s" % overall)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
