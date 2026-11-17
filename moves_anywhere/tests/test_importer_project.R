# test_importer_project.R ######################################################
#
# What:      Offline test of the project-scale importer (PS-6)
# Does:      Checks that create_importer() writes a project importer (five link sections,
#            no county-only sections) for a project run, leaves a county run unchanged
#            (byte-identical to the release 3.1.0 version), and that check_import() compares counts.
# Called by: by hand: Rscript moves_anywhere/tests/test_importer_project.R (from the repo root)
# Reads:     moves_anywhere/inputs_project/, moves_anywhere/inputs_ny/rs_custom.xml, scripts/importer.R
# Writes:    temp folders only (removed at the end)
# Exits:     0 and prints PASS, or prints each failure and exits 1
# Needs:     xml2, dplyr, readr; git (for the release 3.1.0 copy of importer.R, tag v3.1.0)
###############################################################################

library(xml2, warn.conflicts = FALSE)
library(dplyr, warn.conflicts = FALSE)
library(readr, warn.conflicts = FALSE)

fails = c()
check = function(ok, what){ if(!isTRUE(ok)){ fails <<- c(fails, what) } }
tmps = c()
newdir = function(){ d = tempfile("imp_"); dir.create(d); tmps <<- c(tmps, d); d }

source("moves_anywhere/scripts/importer.R")
create_new = create_importer

# 1. Project run ####
d1 = newdir()
invisible(file.copy(list.files("moves_anywhere/inputs_project", full.names = TRUE), d1))
for(f in c("link", "linksourcetypehour", "offnetworklink", "opmodedistribution",
           "driveschedulesecondlink", "avgspeeddistribution", "roadtypedistribution",
           "sourcetypeyear", "startsperdaypervehicle", "sourcetypeyearvmt",
           "totalidlefraction", "sourcetypeagedistribution")){
  writeLines("a,b", paste0(d1, "/_", f, ".csv"))
}
out = create_new(BUCKET = d1, SOURCE = "moves_anywhere/scripts", dir = "/cat")
x = read_xml(out)
imp = xml_find_first(x, "/moves/importer")
check(xml_attr(imp, "mode") == "project", "project: mode is project")
paths = list(
  link = c("link", "_link.csv"),
  linksourcetypehour = c("linkSourceTypeHour", "_linksourcetypehour.csv"),
  driveschedulesecondlink = c("driveScheduleSecondLink", "_driveschedulesecondlink.csv"),
  offnetworklink = c("offNetworkLink", "_offnetworklink.csv"),
  linkopmodedistribution = c("opModeDistribution", "_opmodedistribution.csv"))
for(sec in names(paths)){
  fn = xml_text(xml_find_first(imp, paste0("./", sec, "/parts/", paths[[sec]][1], "/filename")))
  check(!is.na(fn) && endsWith(fn, paths[[sec]][2]), paste0("project: filename of ", sec))
}
for(sec in c("avgspeeddistribution","roadtypedistribution","sourcetypepopulation","starts","vehicletypevmt","idle")){
  check(length(xml_find_all(imp, paste0("./", sec))) == 0, paste0("project: ", sec, " must be absent"))
}
fn = xml_text(xml_find_first(imp, "./agedistribution/parts/sourceTypeAgeDistribution/filename"))
check(endsWith(fn, "_sourcetypeagedistribution.csv"), "project: agedistribution filename")

# 2. County guard: stray _link.csv ####
d2 = newdir()
invisible(file.copy("moves_anywhere/inputs_ny/rs_custom.xml", d2))
writeLines("a,b", paste0(d2, "/_link.csv"))
writeLines("a,b", paste0(d2, "/_sourcetypeagedistribution.csv"))
out2 = create_new(BUCKET = d2, SOURCE = "moves_anywhere/scripts", dir = "/cat")
imp2 = xml_find_first(read_xml(out2), "/moves/importer")
check(xml_attr(imp2, "mode") == "county", "county guard: mode is county")
check(length(xml_find_all(imp2, "./link")) == 0, "county guard: no link section")

# 3. County unchanged against release 3.1.0 ####
# The baseline is the importer.R of the last release before project scale (git tag v3.1.0),
# not HEAD: after this change is committed, HEAD is the new function.
old_file = tempfile(fileext = ".R"); tmps = c(tmps, old_file)
old_code = suppressWarnings(system2("git", c("show", "v3.1.0:moves_anywhere/scripts/importer.R"),
                                    stdout = TRUE, stderr = FALSE))
if(length(old_code) < 50){
  cat("note: git tag v3.1.0 not available here; the county byte-for-byte check was skipped
")
}else{
  writeLines(old_code, old_file)
  env_old = new.env()
  sys.source(old_file, envir = env_old)
  d3 = newdir()
  invisible(file.copy("moves_anywhere/inputs_ny/rs_custom.xml", d3))
  invisible(file.copy(list.files("moves_anywhere/inputs_ny", pattern = "^_.*[.]csv$", full.names = TRUE), d3))
  out_old = env_old$create_importer(BUCKET = d3, SOURCE = "moves_anywhere/scripts", dir = "/cat")
  bytes_old = readBin(out_old, "raw", file.size(out_old))
  out_new = create_new(BUCKET = d3, SOURCE = "moves_anywhere/scripts", dir = "/cat")
  bytes_new = readBin(out_new, "raw", file.size(out_new))
  check(identical(bytes_old, bytes_new), "county: importer.xml differs from the release 3.1.0 version")
}

# 4. check_import() ####
CHECK_IMPORT_TEST = TRUE
source("moves_anywhere/scripts/task_check_import.R")
ok = c(link = 7L, offnetworklink = 1L)
check(identical(check_import(ok, c(link = 7L, offnetworklink = 1L)), ""), "check_import: equal counts")
check(identical(check_import(ok, c(link = 7L, offnetworklink = 0L)),
                "project import failed: offnetworklink has 0 rows, expected 1"), "check_import: difference")
check(identical(check_import(ok, c(link = 7L)),
                "project import failed: offnetworklink has 0 rows, expected 1"), "check_import: missing table")

unlink(tmps, recursive = TRUE)
if(length(fails) > 0){
  cat("FAIL\n", paste0(" - ", fails, collapse = "\n"), "\n", sep = "")
  quit(status = 1)
}
cat("PASS\n")
