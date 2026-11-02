import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compare_outputs as co  # noqa: E402

MO_HEADER = ("MOVESRunID,iterationID,yearID,monthID,pollutantID,processID,"
             "sourceTypeID,regClassID,fuelTypeID,roadTypeID,modelYearID,emissionQuant")
MO_ROWS = [
    "1,1,2022,NA,1,1,21,10,1,5,2020,0.1",
    "1,1,2022,NA,1,1,21,10,1,5,2020,0.2",
    "1,1,2022,NA,2,1,21,10,1,5,2020,3.5",
    "1,1,2022,NA,3,1,31,10,2,3,2019,",
]
ACT_HEADER = ("MOVESRunID,iterationID,activityTypeID,sourceTypeID,monthID,"
              "fuelTypeID,roadTypeID,regClassID,activity")
ACT_ROWS = ["1,1,6,21,NA,1,5,10,0.5", "1,1,1,21,NA,1,5,10,12.25"]
DATA_HEADER = ("year,geoid,pollutant,sourcetype,regclass,fueltype,roadtype,"
               "emissions,vmt,sourcehours,vehicles,starts,idlehours,hoteld,hotelb,hotelo,by")
DATA_ROWS = ["2022,36109,1,11,10,1,1,0.14,NA,NA,NA,NA,NA,NA,NA,NA,1",
             "2022,36109,2,11,10,1,1,0.5,7,NA,NA,NA,NA,NA,NA,NA,1"]


def write(folder, name, header, rows):
    with open(os.path.join(folder, name), "w", newline="") as fh:
        fh.write(header + "\n" + "\n".join(rows) + "\n")


def make_folder(root, label, mo_rows=None, include=("mo", "act", "data")):
    folder = os.path.join(root, label)
    os.makedirs(folder)
    if "mo" in include:
        write(folder, "movesoutput.csv", MO_HEADER, mo_rows or MO_ROWS)
    if "act" in include:
        write(folder, "movesactivityoutput.csv", ACT_HEADER, ACT_ROWS)
    if "data" in include:
        write(folder, "data.csv", DATA_HEADER, DATA_ROWS)
    return folder


def run(a, b, *extra):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = co.main([a, b, *extra])
    return code, out.getvalue()


class CompareOutputsTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, True)

    def test_identical_dirs_pass(self):
        a = make_folder(self.root, "a")
        b = make_folder(self.root, "b")
        code, text = run(a, b)
        self.assertEqual(code, 0)
        self.assertEqual(text.count("PASS  "), 3)
        self.assertIn("OVERALL: PASS", text)

    def test_one_cell_change_fails_and_reports_key(self):
        a = make_folder(self.root, "a")
        changed = list(MO_ROWS)
        changed[2] = "1,1,2022,NA,2,1,21,10,1,5,2020,3.5000000001"
        b = make_folder(self.root, "b", mo_rows=changed)
        code, text = run(a, b)
        self.assertEqual(code, 1)
        self.assertIn("FAIL  movesoutput.csv", text)
        self.assertIn("pollutantID=2", text)
        self.assertIn("emissionQuant", text)

    def test_metadata_only_change_passes(self):
        a = make_folder(self.root, "a")
        changed = [r.replace("1,1,2022", "7,4,2022", 1) for r in MO_ROWS]
        b = make_folder(self.root, "b", mo_rows=changed)
        code, text = run(a, b)
        self.assertEqual(code, 0, text)

    def test_row_order_does_not_matter(self):
        a = make_folder(self.root, "a")
        b = make_folder(self.root, "b", mo_rows=list(reversed(MO_ROWS)))
        code, text = run(a, b)
        self.assertEqual(code, 0, text)

    def test_missing_file_fails(self):
        a = make_folder(self.root, "a")
        b = make_folder(self.root, "b", include=("mo", "data"))
        code, text = run(a, b)
        self.assertEqual(code, 1)
        self.assertIn("FAIL  movesactivityoutput.csv", text)

    def test_missing_in_both_is_skip(self):
        a = make_folder(self.root, "a", include=("mo",))
        b = make_folder(self.root, "b", include=("mo",))
        code, text = run(a, b)
        self.assertEqual(code, 0)
        self.assertIn("SKIP  movesactivityoutput.csv", text)

    def test_extra_key_fails(self):
        a = make_folder(self.root, "a")
        b = make_folder(self.root, "b",
                        mo_rows=MO_ROWS + ["1,1,2022,NA,9,1,21,10,1,5,2020,1.0"])
        code, text = run(a, b)
        self.assertEqual(code, 1)
        self.assertIn("only in B: pollutantID=9", text)

    def test_json_output(self):
        a = make_folder(self.root, "a")
        b = make_folder(self.root, "b")
        code, text = run(a, b, "--json", "--files", "movesoutput,data")
        self.assertEqual(code, 0)
        obj = json.loads(text)
        self.assertEqual(obj["overall"], "PASS")
        self.assertEqual([f["file"] for f in obj["files"]],
                         ["movesoutput.csv", "data.csv"])


if __name__ == "__main__":
    unittest.main()
