#!/usr/bin/env python3
# make_nei_ages.py ############################################################
#
# What:      Developer script that builds county vehicle-age tables (sourcetypeagedistribution) for every county from EPA's NEI county databases.
# Does:      Lists EPA's CDBs_for_all_counties folder for the year, then for each state zip (one at a time) downloads it, reads ONLY
#            sourcetypeagedistribution.MYD from each county database inside (fixed 15-byte MyISAM rows, read in memory, never extracted to disk),
#            writes one part file per state, checks every county, deletes the zip, and finally combines the parts into one gzip CSV.
#            Restartable: a state whose part file exists is skipped. The zips are untrusted data: nothing from them is executed.
#            Sums: a county's vehicle type is a problem only when its age fractions sum outside 1 +/- 1e-4 (EPA's stored doubles give e.g.
#            0.999994: rounding). Within that, each type is rescaled to sum to 1 when a part is written and again when the parts are
#            combined (so parts from older versions are corrected too). The largest |sum - 1| removed is logged per state
#            (log.csv column max_correction) and printed in the summary. Fractions are written with 15 significant digits.
# Usage:     python -I make_nei_ages.py --year 2020 --work <dir> --out <dir> [--states 11,78] [--keep-zips]
#            --year is 2020 or 2023. --states takes state FIPS codes (default: every zip listed).
# Called by: Developer tool: run by hand. Not used by v3 or launch.sh. Design note: docs/audit/project_scale_2026-11/sources/nei_county_ages.md
# Reads:     https://gaftp.epa.gov/air/nei/<year>/doc/supporting_data/onroad/CDBs_for_all_counties/ (listing and zips)
# Writes:    <work>/dl/ (zips, removed after reading), <work>/parts/<year>_<state>.csv, <work>/log.csv,
#            <out>/nei_sourcetypeagedistribution_<year>.csv.gz, <out>/nei_ages_<year>_checks.csv
# Needs:     Python 3 standard library only
# Exit:      0 when every wanted state was read, 1 otherwise (missing states are named).
#
import argparse
import collections
import csv
import gzip
import os
import re
import struct
import sys
import time
import urllib.request
import zipfile

BASE = "https://gaftp.epa.gov/air/nei/{year}/doc/supporting_data/onroad/CDBs_for_all_counties/"
UA = "Mozilla/5.0 (compatible; data-download)"
ROW = 15
FLAG = 0xFD
# 2020 zips: <county db>/file; 2023 zips add one top folder: <2023_CDBs_stateNN>/<county db>/file.
MEMBER = re.compile(r"^(?:[^/\\]+/)?([^/\\]+)/sourcetypeagedistribution\.MYD$", re.IGNORECASE)
FOLDER = re.compile(r"^c(\d{5})y(\d{4})")
ZIPNAME = re.compile(r"^\d{4}_CDBs_state(\d{2})\.zip$", re.IGNORECASE)
HREF = re.compile(r'href="([^"/?][^"]*\.zip)"', re.IGNORECASE)
PART_HEADER = ["countyID", "yearID", "sourceTypeID", "ageID", "ageFraction"]
LOG_HEADER = ["state", "zip", "bytes", "download_seconds", "read_seconds", "counties", "rows", "problems", "max_correction"]
SUM_TOL = 1e-4  # EPA stores doubles that sum to e.g. 0.999994: rounding, not a problem; beyond 1e-4 is a problem


class ReadError(Exception):
    pass


def http_get(url, timeout=600):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    return urllib.request.urlopen(req, timeout=timeout)


def list_zips(year):
    with http_get(BASE.format(year=year), timeout=60) as r:
        text = r.read().decode("utf-8", "replace")
    out = {}
    for name in HREF.findall(text):
        m = ZIPNAME.match(name)
        if m and name.startswith(str(year)):
            out[m.group(1)] = name
    return out


def download(url, dest):
    last = None
    for attempt in (1, 2):
        try:
            with http_get(url) as r, open(dest + ".part", "wb") as fh:
                while True:
                    b = r.read(1 << 20)
                    if not b:
                        break
                    fh.write(b)
            os.replace(dest + ".part", dest)
            return os.path.getsize(dest)
        except Exception as e:  # noqa: BLE001 (retry once on any failure)
            last = e
            print("  download attempt %d failed: %s" % (attempt, e), file=sys.stderr)
    raise ReadError("download failed for %s: %s" % (url, last))


def read_zip(path, year):
    """Return (rows, counties, problems) from every county's sourcetypeagedistribution.MYD."""
    rows = []
    problems = []
    counties = set()
    with zipfile.ZipFile(path) as zf:
        for info in zf.infolist():
            m = MEMBER.match(info.filename)
            if not m:
                continue
            g = FOLDER.match(m.group(1))
            if not g:
                continue
            county = g.group(1)
            if info.file_size % ROW or info.file_size == 0:
                raise ReadError("%s in %s: size %d is not a positive multiple of %d bytes"
                                % (info.filename, os.path.basename(path), info.file_size, ROW))
            b = zf.read(info)
            for i in range(0, len(b), ROW):
                if b[i] != FLAG:
                    raise ReadError("%s in %s: flag byte 0x%02X at row %d, expected 0x%02X"
                                    % (info.filename, os.path.basename(path), b[i], i // ROW, FLAG))
                st, yr, age = struct.unpack("<hhh", b[i + 1:i + 7])
                frac = struct.unpack("<d", b[i + 7:i + 15])[0]
                rows.append((county, yr, st, age, frac))
            counties.add(county)
    if not counties:
        raise ReadError("%s: no county sourcetypeagedistribution.MYD found" % os.path.basename(path))
    return rows, sorted(counties), problems


def check_rows(rows, year):
    """Per-county checks. Returns {county: dict}."""
    by = collections.defaultdict(lambda: collections.defaultdict(list))
    years = collections.defaultdict(set)
    for c, yr, st, age, f in rows:
        by[c][st].append((age, f))
        years[c].add(yr)
    res = {}
    for c in sorted(by):
        probs = []
        sts = by[c]
        if len(sts) != 13:
            probs.append("source_types=%d" % len(sts))
        if years[c] != {int(year)}:
            probs.append("yearID=%s" % sorted(years[c]))
        maxerr = 0.0
        neg = 0
        minage, maxage = 99, -1
        for st, lst in sts.items():
            ages = sorted(a for a, _ in lst)
            minage = min(minage, ages[0])
            maxage = max(maxage, ages[-1])
            # 2020 tables run 0 to 30; the 2023 tables run 0 to 40 (measured). Either must be gap-free from 0.
            if ages not in (list(range(31)), list(range(41))):
                probs.append("ages_st%d" % st)
            s = sum(f for _, f in lst)
            maxerr = max(maxerr, abs(s - 1.0))
            if abs(s - 1.0) > SUM_TOL:
                probs.append("sum_st%d=%.6f" % (st, s))
            if any(f < 0 for _, f in lst):
                neg += 1
                probs.append("negative_st%d" % st)
        res[c] = dict(countyID=c, yearID=year, sourceTypes=len(sts),
                      rows=sum(len(v) for v in sts.values()), minAge=minage, maxAge=maxage,
                      maxSumError="%.3g" % maxerr, negativeTypes=neg,
                      problems=";".join(probs))
    return res


def normalise(rows):
    """Rescale each county's vehicle type so its age fractions sum to exactly 1.
    rows: (county, year, sourceType, age, fraction). Returns (new rows, largest |sum - 1| corrected).
    A type whose sum is outside SUM_TOL (or not positive) is left unchanged, so the check still flags it."""
    sums = collections.defaultdict(float)
    for c, yr, st, age, f in rows:
        sums[(c, st)] += f
    maxcorr = 0.0
    out = []
    for c, yr, st, age, f in rows:
        s = sums[(c, st)]
        if s > 0 and abs(s - 1.0) <= SUM_TOL:
            f = f / s
        out.append((c, yr, st, age, f))
    for s in sums.values():
        if s > 0 and abs(s - 1.0) <= SUM_TOL:
            maxcorr = max(maxcorr, abs(s - 1.0))
    return out, maxcorr


def write_part(path, rows):
    tmp = path + ".tmp"
    with open(tmp, "w", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(PART_HEADER)
        for c, yr, st, age, f in rows:
            w.writerow([c, yr, st, age, "%.15g" % f])
    os.replace(tmp, path)


def append_log(path, line):
    new = not os.path.exists(path)
    if not new:
        # A log written by the older version has no max_correction column: add it to the header.
        with open(path, newline="") as fh:
            lines = fh.read().split("\n")
        if lines and "max_correction" not in lines[0]:
            lines[0] += ",max_correction"
            with open(path, "w", newline="") as fh:
                fh.write("\n".join(lines))
    with open(path, "a", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        if new:
            w.writerow(LOG_HEADER)
        w.writerow(line)


def main():
    ap = argparse.ArgumentParser(description="Build county age tables from EPA NEI county databases.")
    ap.add_argument("--year", type=int, required=True, choices=[2020, 2023])
    ap.add_argument("--work", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--states", default="")
    ap.add_argument("--keep-zips", action="store_true")
    a = ap.parse_args()
    t0 = time.time()
    year = a.year
    dl = os.path.join(a.work, "dl")
    parts = os.path.join(a.work, "parts")
    for d in (dl, parts, a.out):
        os.makedirs(d, exist_ok=True)
    log = os.path.join(a.work, "log.csv")

    listing = list_zips(year)
    if not listing:
        print("No zip files found in the %d listing." % year, file=sys.stderr)
        return 1
    want = sorted(listing)
    if a.states:
        asked = sorted("%02d" % int(s) for s in a.states.split(",") if s.strip())
        unknown = [s for s in asked if s not in listing]
        if unknown:
            print("Not in the %d listing: %s" % (year, ",".join(unknown)), file=sys.stderr)
        want = [s for s in asked if s in listing]
    missing = [s for s in sorted(set(("%02d" % int(x)) for x in a.states.split(",") if x.strip())) if s not in listing] if a.states else []

    failed = []
    for st in want:
        part = os.path.join(parts, "%d_%s.csv" % (year, st))
        if os.path.exists(part):
            print("state %s: part exists, skipped" % st)
            continue
        name = listing[st]
        zpath = os.path.join(dl, name)
        try:
            t1 = time.time()
            size = download(BASE.format(year=year) + name, zpath)
            dsec = time.time() - t1
            t2 = time.time()
            rows, counties, _ = read_zip(zpath, year)
            checks = check_rows(rows, year)
            bad = ["%s:%s" % (c, v["problems"]) for c, v in checks.items() if v["problems"]]
            rows.sort(key=lambda r: (r[0], r[2], r[3]))
            rows, corr = normalise(rows)
            write_part(part, rows)
            rsec = time.time() - t2
            append_log(log, [st, name, size, "%.1f" % dsec, "%.1f" % rsec, len(counties), len(rows), " | ".join(bad), "%.3g" % corr])
            print("state %s: %s, %.1f MB in %.0f s (%.2f MB/s), %d counties, %d rows, %d with problems, largest correction %.3g"
                  % (st, name, size / 1048576, dsec, size / 1048576 / max(dsec, 1e-9), len(counties), len(rows), len(bad), corr))
        except (ReadError, zipfile.BadZipFile, OSError) as e:
            print("state %s FAILED: %s" % (st, e), file=sys.stderr)
            append_log(log, [st, name, "", "", "", "", "", "FAILED: %s" % e])
            failed.append(st)
        finally:
            if not a.keep_zips:
                for p in (zpath, zpath + ".part"):
                    if os.path.exists(p):
                        os.remove(p)

    # Combine the parts of the wanted states.
    allrows = []
    done = []
    corrections = {}
    for st in want:
        part = os.path.join(parts, "%d_%s.csv" % (year, st))
        if not os.path.exists(part):
            continue
        done.append(st)
        strows = []
        with open(part, newline="") as fh:
            rd = csv.reader(fh)
            next(rd)
            for c, yr, s, age, f in rd:
                strows.append((c, int(yr), int(s), int(age), float(f)))
        # Renormalise here too, so parts written by the older version are corrected as well.
        strows, corr = normalise(strows)
        corrections[st] = corr
        allrows.extend(strows)
    allrows.sort(key=lambda r: (r[0], r[2], r[3]))
    outgz = os.path.join(a.out, "nei_sourcetypeagedistribution_%d.csv.gz" % year)
    with open(outgz, "wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as gz:
            gz.write((",".join(PART_HEADER) + "\n").encode())
            for c, yr, s, age, f in allrows:
                gz.write(("%s,%d,%d,%d,%.15g\n" % (c, yr, s, age, f)).encode())
    chk = check_rows(allrows, year)
    chkp = os.path.join(a.out, "nei_ages_%d_checks.csv" % year)
    cols = ["countyID", "yearID", "sourceTypes", "rows", "minAge", "maxAge", "maxSumError", "negativeTypes", "problems"]
    with open(chkp, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, lineterminator="\n")
        w.writeheader()
        for c in sorted(chk):
            w.writerow(chk[c])
    nprob = sum(1 for v in chk.values() if v["problems"])
    print("SUMMARY year %d: states %d, counties %d, rows %d, counties with problems %d, output %s (%d bytes), %.0f s"
          % (year, len(done), len(chk), len(allrows), nprob, outgz, os.path.getsize(outgz), time.time() - t0))
    worst = max(corrections.values()) if corrections else 0.0
    print("Largest correction per state (|sum - 1| removed by renormalising): %s; overall %.3g"
          % (", ".join("%s=%.3g" % (s, corrections[s]) for s in sorted(corrections)), worst))
    lost = sorted(set(want) - set(done)) + missing
    if lost:
        print("MISSING states: %s" % ",".join(sorted(set(lost))), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
