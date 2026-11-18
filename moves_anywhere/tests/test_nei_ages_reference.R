# test_nei_ages_reference.R ####################################################
#
# What:      Offline test of the conversion of NEI county age tables to ages 0 to 40
#            (moves_anywhere/dev/make_nei_ages_reference.R, EPA's Convert_MOVES3_input_to_MOVES5.sql).
# Does:      Builds a small input of three counties (two with ages 0 to 30 for 2020, one with ages 0 to
#            40 for 2023) and checks, against numbers worked out by hand below: the three maximum-age
#            cases (type 43, max 34; type 54, max 44; type 21, max 62); every table sums to 1 with 41
#            ages; types 53 and 62 equal the national table; every county of the input is present; the
#            2023 table is used as given for the other types.
# Called by: Developer tool. Run from the repository root: Rscript moves_anywhere/tests/test_nei_ages_reference.R
# Reads:     nothing on disk but dev/make_nei_ages_reference.R
# Writes:    nothing
# Exits:     0 and prints PASS; 1 and prints what failed
###############################################################################
#
# Hand-worked cases. Every 2020 type has ages 0-29 at 0.88/30 each and age 30 = t = 0.12.
# Rule: new30 = t * 2 / (max + 2 - 30); age a in 30..max = new30 * (1 - (a - 30) / (max + 1 - 30)).
#
# Case A, type 43, max 34 (under 40): new30 = 0.12 * 2 / 6 = 0.04. Line over ages 30..34 is
#   0.04 * (5, 4, 3, 2, 1) / 5 = 0.04, 0.032, 0.024, 0.016, 0.008 (sum 0.12 = t). Ages 35 to 40 = 0.
# Case B, type 54, max 44 (just over 40): new30 = 0.12 * 2 / 16 = 0.015. Line = 0.015 * (15 - (a-30)) / 15:
#   age 31 = 0.015 * 14/15 = 0.014; age 39 = 0.015 * 6/15 = 0.006. Ages 40..44 are summed into 40:
#   0.015 * (5+4+3+2+1)/15 = 0.015.
# Case C, type 21, max 62 (far over 40): new30 = 0.12 * 2 / 34 = 0.12/17. Line = new30 * (33 - (a-30)) / 33:
#   age 31 = new30 * 32/33. Ages 40..62 summed into 40: new30 * (23+22+...+1)/33 = new30 * 276/33
#   = 0.12 / 17 * 276 / 33 = 0.0590451...
# (In every case the line sums back to t, so each table still sums to 1 before renormalising.)

suppressPackageStartupMessages({ library(dplyr); library(readr) })
source("moves_anywhere/dev/make_nei_ages_reference.R")

failures = character(0)
check = function(ok, label){ if(!isTRUE(ok)){ failures <<- c(failures, label) } }
near = function(a, b, tol = 1e-12){ isTRUE(all(abs(a - b) < tol)) }

types = c(11, 21, 31, 32, 41, 42, 43, 51, 52, 53, 54, 61, 62)
t_tail = 0.12
mk2020 = function(county) data.frame(countyID = county, yearID = 2020L, sourceTypeID = rep(types, each = 31),
                                     ageID = rep(0:30, times = 13),
                                     ageFraction = rep(c(rep(0.88 / 30, 30), t_tail), times = 13))
mk2023 = function(county) data.frame(countyID = county, yearID = 2023L, sourceTypeID = rep(types, each = 41),
                                     ageID = rep(0:40, times = 13), ageFraction = rep(1 / 41, 13 * 41))
inputs = bind_rows(mk2020("36109"), mk2020("01001"), mk2023("06037"))
# national stand-in: long-haul weight proportional to age + 1 (sum 861), the same for both years
nat_one = function(y) data.frame(sourceTypeID = rep(types, each = 41), yearID = y, ageID = rep(0:40, 13),
                                 ageFraction = rep(0:40 + 1, 13) / 861)
national = bind_rows(nat_one(2020L), nat_one(2023L))

res = build_ages_reference(inputs, national)
get = function(g, y, s, a) res$ageFraction[res$geoid == g & res$year == y & res$sourceTypeID == s & res$ageID %in% a]

# shape
check(identical(names(res), c("geoid", "year", "sourceTypeID", "ageID", "ageFraction")), "columns")
check(is.character(res$geoid) && all(nchar(res$geoid) == 5), "geoid is a 5-character string")
check(nrow(res) == 3 * 13 * 41, "rows = counties x 13 types x 41 ages")
check(setequal(unique(res$geoid), c("36109", "01001", "06037")), "every county of the inputs present")
check(identical(sort(unique(res$ageID)), 0:40), "ages 0 to 40")
sums = res %>% group_by(geoid, year, sourceTypeID) %>% summarise(s = sum(ageFraction), n = n(), .groups = "drop")
check(near(sums$s, 1), "each county-year-type sums to 1")
check(all(sums$n == 41L), "41 ages per county-year-type")
# ages 0-29 unchanged for a converted type (0.88/30 = 0.029333...)
check(near(get("36109", 2020L, 43, 0:29), 0.88 / 30), "ages 0-29 unchanged")
# Case A
check(near(get("36109", 2020L, 43, 30:34), c(0.04, 0.032, 0.024, 0.016, 0.008)), "case A: type 43 ages 30-34")
check(near(get("36109", 2020L, 43, 35:40), rep(0, 6)), "case A: type 43 ages 35-40 zero")
# Case B
check(near(get("36109", 2020L, 54, 30), 0.015), "case B: type 54 age 30")
check(near(get("36109", 2020L, 54, 31), 0.014), "case B: type 54 age 31")
check(near(get("36109", 2020L, 54, 39), 0.006), "case B: type 54 age 39")
check(near(get("36109", 2020L, 54, 40), 0.015), "case B: type 54 age 40 (ages 40-44 summed)")
# Case C
check(near(get("36109", 2020L, 21, 30), 0.12 / 17), "case C: type 21 age 30")
check(near(get("36109", 2020L, 21, 31), 0.12 / 17 * 32 / 33), "case C: type 21 age 31")
check(near(get("36109", 2020L, 21, 40), 0.12 / 17 * 276 / 33), "case C: type 21 age 40 (ages 40-62 summed)")
# long-haul equals national, both years and both converted and as-given tables
for(g in c("36109", "01001")) for(s in c(53, 62)) check(near(get(g, 2020L, s, 0:40), (0:40 + 1) / 861), paste("long-haul national", g, s))
check(near(get("06037", 2023L, 53, 0:40), (0:40 + 1) / 861), "long-haul national 2023 type 53")
# 2023 as given for another type
check(near(get("06037", 2023L, 21, 0:40), 1 / 41), "2023 table used as given")
# fails loudly on a missing type
check(inherits(try(build_ages_reference(inputs %>% filter(!(countyID == "06037" & sourceTypeID == 11)), national), silent = TRUE), "try-error"), "missing type stops")

if(length(failures) > 0){ cat("FAIL:\n", paste0(" - ", failures, collapse = "\n"), "\n", sep = ""); quit(status = 1) }
cat("PASS: test_nei_ages_reference
")
