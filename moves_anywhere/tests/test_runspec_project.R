# test_runspec_project.R ######################################################
#
# What:      Offline test of project_runspec() in scripts/project_functions.R.
# Does:      Builds a runspec with catr::custom_rs() as task_runspec.R does for LEVEL=project, turns it
#            into a project runspec and checks domain, time, road types, processes and rules R1 to R10.
#            Prints (does not assert) which element and attribute names differ from the project fixture.
# Called by: Developer tool and tests/run_gate.sh. Not part of a run.
#            Run from the repository root: Rscript moves_anywhere/tests/test_runspec_project.R
# Reads:     moves_anywhere/inputs_project/rs_custom.xml; needs catr installed
# Writes:    temporary folders only
# Exits:     0 and prints PASS; 1 and prints what failed
###############################################################################

suppressPackageStartupMessages({ library(xml2); library(catr) })
source("moves_anywhere/scripts/project_functions.R")

failures = character(0)
check = function(ok, label){ if(!isTRUE(ok)){ failures <<- c(failures, label) } }
msg = function(expr){ tryCatch({ expr; "no error" }, error = function(e){ conditionMessage(e) }) }

# 1. Make the base runspec the way task_runspec.R does ####

made = character(0)
mkdir = function(){ d = tempfile("rp_"); dir.create(d); made <<- c(made, d); d }
base = function(dir){
  path = file.path(dir, "rs_custom.xml")
  invisible(capture.output(catr::custom_rs(
    .geoid = "36109", .year = 2022, .pollutants = c(98, 3, 2, 31, 33, 110, 100, 106, 107, 116, 117),
    .rate = FALSE, .level = "county", .geoaggregation = "link", .timeaggregation = "hour",
    .path = path
  )))
  path
}

# 2. Road types 1, 4, 5 ####

dir = mkdir()
path = base(dir)
project_runspec(path, 7, 5, 8, c(1, 4, 5))
writeLines("linkID,countyID,zoneID,roadTypeID", file.path(dir, "link.csv"))
check(is_project(path), "is_project")
check(msg(project_check(path, BUCKET = dir)) == "no error", "project_check passes")
s = project_spec(path)
check(identical(s$month, 7L) && identical(s$day, 5L) && identical(s$hour, 8L), "month, day, hour")
check(identical(s$hourday, 85L), "hourday 85")
check(identical(sort(s$roadtypes), c(1L, 4L, 5L)), "roadtypes 1, 4, 5")
check(all(s$processes %in% c(1, 2, 9, 10, 15, 16, 17, 90, 91)), "processes subset")
check(all(c(1, 2) %in% s$processes), "processes include 1 and 2")
check(identical(s$year, 2022L) && identical(s$geoid, 36109L), "year and county kept")

# 3. Road types 4, 5 only: no starts ####

dir2 = mkdir()
path2 = base(dir2)
project_runspec(path2, 7, 5, 8, c(4, 5))
s2 = project_spec(path2)
check(all(s2$processes %in% c(1, 9, 10, 15)), "no off-network: processes subset")
check(length(s2$start_polprocess) == 0, "no off-network: no start_polprocess")
check(identical(sort(s2$roadtypes), c(4L, 5L)), "roadtypes 4, 5")

# 4. A road type custom_rs did not write ####

dir3 = mkdir()
path3 = base(dir3)
check(msg(project_runspec(path3, 7, 5, 8, c(1, 6))) == "runspec has no road type 6", "missing road type message")

# 5. Differences from the fixture (printed, not asserted) ####

shape = function(f){
  x = read_xml(f)
  nodes = xml_find_all(x, "//*")
  paste(vapply(nodes, function(n){
    paste0(gsub("[[][0-9]+[]]", "", xml_path(n)), "@", paste(sort(names(xml_attrs(n))), collapse = ","))
  }, ""))
}
a = unique(shape(path)); b = unique(shape("moves_anywhere/inputs_project/rs_custom.xml"))
cat("In project_runspec result, not in fixture:\n"); print(setdiff(a, b))
cat("In fixture, not in project_runspec result:\n"); print(setdiff(b, a))

# 6. Result ####

unlink(made, recursive = TRUE)
if(length(failures) > 0){
  cat("FAIL:\n", paste0(" - ", failures, collapse = "\n"), "\n", sep = "")
  quit(status = 1)
}
cat("PASS\n")
