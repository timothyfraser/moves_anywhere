# inputs_project

A project-scale test run (MOVES domain PROJECT): Tompkins County, NY, 2022, a July weekday, 8 to 9 am.
Seven links: five road links, one with a second-by-second drive schedule, and one parking lot.
Inputs: `rs_custom.xml`, `link.csv`, `driveschedulesecondlink.csv`, `offnetworklink.csv`.
Gold results from the image: `linkdata.csv`, `movesoutput.csv`, `movesactivityoutput.csv` (used by `tests/test_project.sh`).

Guide: [docs/README_project_scale.md](../../docs/README_project_scale.md).

The reference results were regenerated on 2026-11-18 with travel-weighted vehicle ages (the 3.2.0 default). Against the earlier results, CO2 on the seven links falls by 3.8 to 7.5 percent (total 4.1 percent), NOx by 27 to 53 percent (total 47 percent), exhaust PM2.5 by 52 to 65 percent (total 63 percent) and CO by 32 to 34 percent. Miles and source hours are unchanged. Link by link: `docs/audit/project_scale_2026-11/release/gold_change.csv` in the build repository.
