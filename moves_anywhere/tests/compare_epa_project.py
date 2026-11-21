#!/usr/bin/env python
# compare_epa_project.py ######################################################
#
# What:      Compares a MOVES Anywhere project run's movesoutput.csv with EPA's answer key
#            (inputs_epa_project/epa_movesoutput.csv), grams per row, within a relative tolerance.
# Does:      Takes EPA's rows for one MOVESRunID (--run 1 = average speeds, 2 = drive schedules), joins on
#            linkID, processID, sourceTypeID, pollutantID and fuelTypeID. A key column is used only where
#            both sides carry it (non-blank in every row); where one side is blank and the other not
#            (EPA leaves fuelTypeID blank, we may not), the side that has it is summed to the common key.
#            Zero on both sides is equal. A row on one side only counts as a failure.
# Run 1:     EPA's file holds two MOVESRunID values of 21 rows. In the drive-schedule run (run 2) links 1 and
#            2 differ and links 3 to 6 are identical to the average-speed run. The README of
#            inputs_epa_project names run 1 as the average-speed run, and the drive-schedule file for run 2
#            covers links 1 and 2 only (their mean speeds, 25.0 and 35.0 mph, equal link.csv's average
#            speeds), so a run from link.csv alone is MOVESRunID 1. The script prints which ID it took.
# Called by: tests/test_epa_project.sh. Also run by hand.
# Reads:     the two CSV files given
# Writes:    --out comparison.csv (one row per key), if given
# Exits:     0 when every row is within tolerance and nothing is missing, else 1; 2 on a usage error
# Usage: python -I -B compare_epa_project.py <epa_movesoutput.csv> <our movesoutput.csv> [--run 1|2] [--tol 0.01] [--out comparison.csv]
###############################################################################

import csv
import sys

KEYS = ["linkID", "processID", "sourceTypeID", "pollutantID", "fuelTypeID"]
RUN_NOTE = {
    "1": "average speeds from link.csv (links 1 and 2 have no drive schedule)",
    "2": "drive schedules on links 1 and 2 (the only rows that differ from run 1)",
}


def usage():
    print(__doc__.split("# Usage: ")[-1].split("\n")[0] if False else
          "usage: python -I -B compare_epa_project.py <epa_movesoutput.csv> <our movesoutput.csv> "
          "[--run 1|2] [--tol 0.01] [--out comparison.csv]", file=sys.stderr)


def blank(v):
    return v is None or v.strip() == "" or v.strip().upper() == "NA"


def read_rows(path):
    with open(path, newline="") as fh:
        return list(csv.DictReader(fh))


def main(argv):
    pos, opts, i = [], {"--run": "1", "--tol": "0.01", "--out": None}, 0
    while i < len(argv):
        a = argv[i]
        if a in opts:
            if i + 1 >= len(argv):
                usage()
                return 2
            opts[a] = argv[i + 1]
            i += 2
        elif a in ("-h", "--help"):
            usage()
            return 0
        elif a.startswith("--"):
            usage()
            return 2
        else:
            pos.append(a)
            i += 1
    if len(pos) != 2 or opts["--run"] not in ("1", "2"):
        usage()
        return 2
    try:
        tol = float(opts["--tol"])
    except ValueError:
        usage()
        return 2
    run = opts["--run"]

    epa_all = read_rows(pos[0])
    ours = read_rows(pos[1])
    ids = sorted({r["MOVESRunID"] for r in epa_all})
    epa = [r for r in epa_all if r["MOVESRunID"] == run]
    print("EPA MOVESRunID values in file: %s; took %s as run %s: %s" % (", ".join(ids), run, run, RUN_NOTE[run]))
    if not epa:
        print("FAIL: EPA file has no rows for MOVESRunID %s" % run)
        return 1

    # Key columns both sides carry in every row
    keys = [k for k in KEYS
            if k in epa[0] and ours and k in ours[0]
            and not any(blank(r[k]) for r in epa) and not any(blank(r[k]) for r in ours)]
    dropped = [k for k in KEYS if k not in keys]
    print("Join key: %s" % ", ".join(keys))
    if dropped:
        print("Not in the key (blank on a side): %s; the side that has them is summed to the common key" % ", ".join(dropped))

    def agg(rows):
        d = {}
        for r in rows:
            k = tuple(r[c].strip() for c in keys)
            d[k] = d.get(k, 0.0) + float(r["emissionQuant"])
        return d

    e, o = agg(epa), agg(ours)
    out, fails = [], 0
    for k in sorted(set(e) | set(o), key=lambda t: tuple(int(float(x)) for x in t)):
        eg, og = e.get(k), o.get(k)
        if eg is None or og is None:
            status, ad, rd, ok = ("missing in EPA" if eg is None else "missing in ours"), "", "", "no"
        else:
            ad = abs(og - eg)
            if eg == 0 and og == 0:
                rd = 0.0
            elif eg == 0:
                rd = float("inf")
            else:
                rd = ad / abs(eg)
            ok = "yes" if rd <= tol else "no"
            status = "both"
        if ok == "no":
            fails += 1
        out.append(list(k) + [("" if eg is None else repr(eg)), ("" if og is None else repr(og)),
                              ("" if ad == "" else repr(ad)), ("" if rd == "" else repr(rd)), ok, status])
    header = keys + ["epa_grams", "our_grams", "abs_diff", "rel_diff", "within_tol", "status"]
    if opts["--out"]:
        with open(opts["--out"], "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(header)
            w.writerows(out)
    for r in out:
        if r[-2] == "no":
            print("FAIL  %s  EPA=%s ours=%s rel=%s (%s)" % (
                " ".join("%s=%s" % (c, v) for c, v in zip(keys, r[:len(keys)])),
                r[len(keys)], r[len(keys) + 1], r[len(keys) + 3], r[-1]))
    print("%d row(s), %d within tol %g, %d failing" % (len(out), len(out) - fails, tol, fails))
    print("PASS" if fails == 0 else "FAIL")
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
