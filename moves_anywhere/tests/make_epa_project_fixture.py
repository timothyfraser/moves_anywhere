#!/usr/bin/env python3
"""make_epa_project_fixture.py: build moves_anywhere/inputs_epa_project/ from EPA's Module 7 workbooks.

What:      Reads the US EPA MOVES5 Hands-on Training Course (September 2025), Module 7 Project
           Exercise, from the training zip and writes the input tables in MOVES Anywhere's folder format.
Usage:     python -I make_epa_project_fixture.py <moves5-training-files-2025-09.zip> <output folder>
Reads:     the zip only (xlsx files are read as zip-of-XML; nothing from the zip is executed)
Writes:    csv files into the output folder; running it twice gives identical files.
Not done:  the run specification (rs_custom.xml) and the answer-key output tables are handled by hand
           and by a MariaDB decode (see the folder README); this script leaves them alone.
"""
import csv
import io
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
MOD = "Module 7 - Project Exercise/"


def col_index(ref):
    letters = re.match(r"[A-Z]+", ref).group(0)
    n = 0
    for ch in letters:
        n = n * 26 + ord(ch) - 64
    return n - 1


def read_xlsx(data):
    """Return {sheet name: list of rows (lists of strings)}."""
    z = zipfile.ZipFile(io.BytesIO(data))
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        root = ET.fromstring(z.read("xl/sharedStrings.xml"))
        for si in root.findall("m:si", NS):
            shared.append("".join(t.text or "" for t in si.iter("{%s}t" % NS["m"])))
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    target = {r.get("Id"): r.get("Target") for r in rels}
    out = {}
    for sh in wb.find("m:sheets", NS):
        rid = sh.get("{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id")
        path = target[rid].lstrip("/")
        if not path.startswith("xl/"):
            path = "xl/" + path
        root = ET.fromstring(z.read(path))
        rows = []
        for r in root.iter("{%s}row" % NS["m"]):
            cells = {}
            for c in r.findall("m:c", NS):
                t = c.get("t")
                v = c.find("m:v", NS)
                if t == "s" and v is not None:
                    val = shared[int(v.text)]
                elif t == "inlineStr":
                    val = "".join(x.text or "" for x in c.iter("{%s}t" % NS["m"]))
                elif v is not None and v.text is not None:
                    val = v.text
                else:
                    val = ""
                cells[col_index(c.get("r"))] = val
            if cells:
                rows.append([cells.get(i, "") for i in range(max(cells) + 1)])
        out[sh.get("name")] = rows
    return out


def num(s):
    """Excel stores numbers as text like 0.1 or 1E-3; print them plainly and stably."""
    s = s.strip()
    try:
        f = float(s)
    except ValueError:
        return s
    if f == int(f) and abs(f) < 1e15:
        return str(int(f))
    return repr(f)


def write_csv(path, header, rows):
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(header)
        for r in rows:
            w.writerow(r)
    return len(rows)


def main(zip_path, outdir):
    import os
    os.makedirs(outdir, exist_ok=True)
    z = zipfile.ZipFile(zip_path)
    names = [n for n in z.namelist() if MOD in n]

    def find(suffix):
        hits = [n for n in names if n.endswith(suffix)]
        if len(hits) != 1:
            raise SystemExit("expected one %s, found %s" % (suffix, hits))
        return hits[0]

    summary = []
    # (workbook, sheet, output file, columns to drop, add a FIPS column)
    plan = [
        ("Answer Key/links.xlsx", "link", "link.csv", [], False),
        ("Answer Key/link_source_type.xlsx", "linkSourceTypeHour", "linksourcetypehour.csv", [], False),
        ("Answer Key/off-network.xlsx", "offNetworkLink", "offnetworklink.csv", ["zoneID"], False),
        ("Answer Key/opmode_distribution.xlsx", "opModeDistribution", "opmodedistribution.csv", [], False),
        ("Answer Key/hotelling.xlsx", "hotellingActivityDistribution", "hotellingactivitydistribution.csv", [], True),
        ("Answer Key/link_drive_schedule.xlsx", "driveScheduleSecondLink", "driveschedulesecondlink_run2.csv", [], False),
        ("age_distribution.xlsx", "SourceTypeAgeDistribution", "sourcetypeagedistribution.csv", [], True),
        ("fuels.xlsx", "FuelSupply", "fuelsupply.csv", [], True),
        ("fuels.xlsx", "FuelFormulation", "fuelformulation.csv", [], True),
        ("fuels.xlsx", "FuelUsageFraction", "fuelusagefraction.csv", [], True),
        ("fuels.xlsx", "avft", "avft.csv", [], True),
        ("met.xlsx", "zoneMonthHour", "zonemonthhour.csv", [], True),
    ]
    for wbname, sname, outname, drop, fips in plan:
        rows = read_xlsx(z.read(find(wbname)))[sname]
        header = [h.strip() for h in rows[0]]
        keep = [i for i, h in enumerate(header) if h not in drop]
        body = []
        for r in rows[1:]:
            r = r + [""] * (len(header) - len(r))
            row = [num(r[i]) for i in keep]
            if any(c != "" for c in row):
                body.append(row + (["26161"] if fips else []))
        os.makedirs(os.path.dirname(os.path.join(outdir, outname)), exist_ok=True)
        n = write_csv(os.path.join(outdir, outname), [header[i] for i in keep] + (["FIPS"] if fips else []), body)
        summary.append("%s [%s] -> %s: %d rows" % (wbname, sname, outname, n))
    print("\n".join(summary))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
