# test_link_mix.R #############################################################
#
# What:      Offline test of links_mix() (link_mix.R), the vehicle mix from federal truck counts.
# Does:      Fakes get_table() and the county tables with literal data in a temp folder; checks that
#            shares sum to 1, the truck share lands on types 52 to 62, links without (or with
#            impossible) counts get no rows, a run without type 62 puts the combination share on 61,
#            and adapt_linksourcetypehour() accepts the result written as linksourcetypehour.csv.
# Called by: run by hand from the repository root: Rscript moves_anywhere/tests/test_link_mix.R
# Reads:     moves_anywhere/inputs_project/rs_custom.xml, moves_anywhere/scripts/*.R
# Writes:    a temp folder only (removed at the end)
# Exits:     0 and prints PASS, or prints what failed and exits 1
###############################################################################

suppressPackageStartupMessages({ library(dplyr); library(readr); library(tidyr); library(stringr) })
source("moves_anywhere/scripts/adapt_functions.R")
source("moves_anywhere/scripts/project_functions.R")
source("moves_anywhere/scripts/adapt_link.R")
source("moves_anywhere/scripts/link_mix.R")

# The default database is not available here: a literal avgspeedbin
get_table = function(tablename){
  if(tablename == "avgspeedbin"){
    return(data.frame(avgSpeedBinID = 1:3, avgBinSpeed = c(5, 20, 60)))
  }
  stop(paste0("test has no default table ", tablename))
}

failures = character(0)
check = function(ok, what){ if(!isTRUE(ok)){ failures <<- c(failures, what) } }
near = function(a, b){ isTRUE(abs(a - b) < 1e-6) }

# 1. A project run in a temp folder ####
root = tempfile("link_mix_")
dir.create(root)
rs = paste0(root, "/rs_custom.xml")
file.copy("moves_anywhere/inputs_project/rs_custom.xml", rs)
spec = project_spec(rs)
st = spec$sourcetypes

# County tables: every type carries mileage, 1e5 times its position, the same on road types 4 and 5
vmt_of = 1e5 * seq_along(st)
B = tempfile("bucket_", tmpdir = root)
dir.create(B)
write_csv(data.frame(yearID = 2022, sourceTypeID = st, VMT = vmt_of), paste0(B, "/_sourcetypeyearvmt.csv"))
write_csv(data.frame(sourceTypeID = st, monthID = 7, monthVMTFraction = 0.1), paste0(B, "/_monthvmtfraction.csv"))
write_csv(expand.grid(sourceTypeID = st, monthID = 7, roadTypeID = c(4, 5), dayID = 5) %>%
            mutate(dayVMTFraction = 0.7), paste0(B, "/_dayvmtfraction.csv"))
write_csv(expand.grid(sourceTypeID = st, roadTypeID = c(4, 5), dayID = 5, hourID = 8) %>%
            mutate(hourVMTFraction = 0.06), paste0(B, "/_hourvmtfraction.csv"))
write_csv(expand.grid(sourceTypeID = st, roadTypeID = c(1, 4, 5)) %>%
            mutate(roadTypeVMTFraction = ifelse(roadTypeID == 1, 0, 0.5)), paste0(B, "/_roadtypedistribution.csv"))
write_csv(expand.grid(sourceTypeID = st, roadTypeID = c(4, 5), hourDayID = 85, avgSpeedBinID = 2, avgSpeedFraction = 1),
          paste0(B, "/_avgspeeddistribution.csv"))

links = data.frame(
  linkID = 1:6,
  roadTypeID = c(5, 5, 4, 5, 5, 4),
  aadt = c(10000, 10000, 10000, 10000, 10000, 10000),
  aadt_single_unit = c(1000, NA, 800, 9000, 500, 100),
  aadt_combination = c(500, NA, NA, 2000, 0, 100),
  direction = c("one-way", "one-way", "one-way", "one-way", "remainder", "primary"),
  stringsAsFactors = FALSE)

# 2. The shares ####
res = links_mix(links, rs, B, spec)
src = attr(res, "sources")
check(identical(names(res), c("linkID", "sourceTypeID", "sourceTypeHourFraction")), "result columns")
check(setequal(res$linkID, c(1, 6)), "rows only for links 1 and 6 (no counts, exceeding counts, remainder skipped)")
sums = res %>% group_by(linkID) %>% summarise(s = sum(sourceTypeHourFraction))
check(all(abs(sums$s - 1) < 1e-9), "shares sum to 1 per link")
check(all(table(res$linkID) == length(st)), "one row per run vehicle type")
l1 = res %>% filter(linkID == 1)
check(near(sum(l1$sourceTypeHourFraction[l1$sourceTypeID %in% c(52, 53, 54, 61, 62)]), 0.15), "link 1: 15% in types 52 to 62")
check(near(sum(l1$sourceTypeHourFraction[l1$sourceTypeID %in% c(52, 53, 54)]), 0.10), "link 1: 10% single-unit")
check(near(sum(l1$sourceTypeHourFraction[l1$sourceTypeID %in% c(61, 62)]), 0.05), "link 1: 5% combination")
check(near(sum(l1$sourceTypeHourFraction[!l1$sourceTypeID %in% c(52, 53, 54, 61, 62)]), 0.85), "link 1: 85% elsewhere")
# Within the single-unit group: in proportion to the default mix (vmt by position in st)
w = vmt_of[match(c(52, 53, 54), st)]
check(near(l1$sourceTypeHourFraction[l1$sourceTypeID == 53], 0.10 * w[2] / sum(w)), "link 1: type 53 in proportion to the default")
# Remainder: in proportion to the default with the five types removed
rest = st[!st %in% c(52, 53, 54, 61, 62)]
wr = vmt_of[match(rest, st)]
check(near(l1$sourceTypeHourFraction[l1$sourceTypeID == 21], 0.85 * vmt_of[match(21, st)] / sum(wr)), "link 1: type 21 share of the remainder")
check(!any(res$linkID %in% c(2, 3, 4, 5)), "no rows for links without counts, with one count, exceeding, or remainder")

# Sources
check(nrow(src) == 3, "sources: links 1 and 6 derived, link 4 default")
s1 = src %>% filter(linkID == 1)
check(s1$field == "vehicle mix" && s1$source == "derived" && near(s1$value, 15), "source row of link 1")
check(grepl("single-unit 10.0% and combination 5.0% from federal truck counts; other types by the county default", s1$detail, fixed = TRUE), "source detail text")
check(grepl("buses", s1$detail, fixed = TRUE), "source detail names the bus simplification")
s4 = src %>% filter(linkID == 4)
check(nrow(s4) == 1 && s4$source == "default" && s4$detail == "truck counts exceed the total count; default mix used", "default source row, truck counts above total")
check(!any(src$linkID %in% c(2, 3, 5)), "no source rows for links without counts or remainder links")

# Nothing eligible: zero rows, empty sources
none = links_mix(links[c(2, 3), ], rs, B, spec)
check(nrow(none) == 0 && nrow(attr(none, "sources")) == 0, "zero rows when no link has both counts")

# 3. A run without type 62 ####
spec62 = spec
spec62$sourcetypes = setdiff(st, 62)
r62 = links_mix(links[1, ], rs, B, spec62)
check(!62 %in% r62$sourceTypeID, "no rows for type 62 outside the run")
check(near(r62$sourceTypeHourFraction[r62$sourceTypeID == 61], 0.05), "whole combination share on type 61")
check(near(sum(r62$sourceTypeHourFraction), 1), "shares sum to 1 without type 62")
# No combination type at all: its share joins the remainder
specnc = spec
specnc$sourcetypes = setdiff(st, c(61, 62))
rnc = links_mix(links[1, ], rs, B, specnc)
check(near(sum(rnc$sourceTypeHourFraction[rnc$sourceTypeID %in% c(52, 53, 54)]), 0.10) && near(sum(rnc$sourceTypeHourFraction), 1),
      "combination share added to the remainder when no combination type is in the run")

# 4. The project adapter accepts the file ####
A = tempfile("bucket_", tmpdir = root)
dir.create(A)
for(f in list.files(B, pattern = "^_", full.names = TRUE)){ file.copy(f, A) }
link_csv = data.frame(
  linkID = c(1, 2, 3, 4), roadTypeID = c(5, 4, 5, 1),
  linkLength = c(0.5, 1, 0.5, NA), linkVolume = c(800, 3000, 800, NA),
  linkAvgSpeed = c(25, 40, 25, NA), linkDescription = c("counted", "no counts", "exceeding", "off-network"))
write_csv(link_csv, paste0(A, "/link.csv"))
adapt_link(rs, A)
mine = links_mix(links[1:3, ], rs, A, spec)
write_csv(as.data.frame(mine), paste0(A, "/linksourcetypehour.csv"))
ok = tryCatch({ adapt_linksourcetypehour(rs, A); "ok" }, error = function(e) conditionMessage(e))
check(identical(ok, "ok"), paste0("adapt_linksourcetypehour accepts the file (got: ", ok, ")"))
lm = read_csv(paste0(A, "/_linksourcetypehour.csv"), show_col_types = FALSE)
check(setequal(unique(lm$linkID), c(1, 2, 3)), "adapter gives every road link a mix (default for links 2 and 3)")
l1a = lm %>% filter(linkID == 1)
check(near(sum(l1a$sourceTypeHourFraction[l1a$sourceTypeID %in% c(52, 53, 54, 61, 62)]), 0.15), "link 1 truck share kept by the adapter")

# 5. Result ####
unlink(root, recursive = TRUE)
if(length(failures) > 0){
  cat("FAIL\n"); cat(paste0(" - ", failures, collapse = "\n"), "\n")
  quit(status = 1)
}
cat("PASS\n")
