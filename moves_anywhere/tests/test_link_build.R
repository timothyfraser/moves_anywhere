# test_link_build.R ###########################################################
#
# What:      Test of scripts/link_build.R (HPMS sections to links)
# Does:      Builds literal sections and checks links_build: the four road types, merging of equal
#            consecutive sections, a new link on a change of aadt or a gap, the 2-mile stop, two-way
#            sections split into primary and opposite links, sections without a count tallied in
#            "uncounted", facility_type 6 dropped and counted in "dropped", source rows for every link,
#            and empty input. Then runs the saved 40-section Ithaca fixture through links_parse_sections
#            and links_build and prints the counts.
# Called by: Developer tool and tests/run_gate.sh. Not part of a run.
#            Run from the repository root: Rscript moves_anywhere/tests/test_link_build.R
# Reads:     moves_anywhere/tests/fixtures/links/hpms_ny2025_ithaca_box_40.geojson
# Writes:    nothing
# Exits:     0 and prints PASS; 1 and prints what failed
###############################################################################

source("moves_anywhere/scripts/link_sources.R")
source("moves_anywhere/scripts/link_build.R")

failures = character(0)
check = function(ok, label){ if(!isTRUE(ok)){ failures <<- c(failures, label) } }
near = function(a, b, tol = 1e-9){ length(a) == length(b) && all(abs(a - b) < tol) }

# 1. Literal sections ####

#' One section; geometry is a straight line from (begin, begin) to (end, end), so joints match
sec = function(route_id = "R1", begin_point = 0, end_point = 0.1, f_system = 3, urban_id = 41914,
               facility_type = 1, through_lanes = 2, aadt = 5000, aadt_single_unit = 200,
               aadt_combination = 50, k_factor = NA_real_, dir_factor = NA_real_, speed_limit = 30,
               section_length = end_point - begin_point, data_year = NA_real_){
  g = matrix(c(begin_point, end_point, begin_point, end_point), ncol = 2, dimnames = list(NULL, c("lon", "lat")))
  tibble::tibble(route_id = route_id, begin_point = begin_point, end_point = end_point, f_system = f_system,
                 urban_id = urban_id, facility_type = facility_type, through_lanes = through_lanes,
                 aadt = aadt, aadt_single_unit = aadt_single_unit, aadt_combination = aadt_combination,
                 k_factor = k_factor, dir_factor = dir_factor, speed_limit = speed_limit,
                 section_length = section_length, data_year = data_year, parts = 1L, geometry = list(g))
}
with_year = function(df, y = 2025L){ attr(df, "year") = y; df }

# 2. Road type ####

rt = function(f, u){ links_build(with_year(sec(f_system = f, urban_id = u)))$roadTypeID }
check(identical(rt(1, 99999), 2L), "f_system 1 rural is road type 2")
check(identical(rt(2, NA), 2L), "f_system 2 with NA urban_id is road type 2")
check(identical(rt(4, 99999), 3L), "f_system 4 rural is road type 3")
check(identical(rt(1, 41914), 4L), "f_system 1 urban is road type 4")
check(identical(rt(2, 41914), 4L), "f_system 2 urban is road type 4")
check(identical(rt(7, 41914), 5L), "f_system 7 urban is road type 5")

# access_control counts only on class 2: 1 or missing restricted, 2 and 3 unrestricted
rta = function(f, u, a){ links_build(with_year(dplyr::mutate(sec(f_system = f, urban_id = u), access_control = a))) }
rts = function(L){ s = attr(L, "sources"); s[s$field == "roadTypeID", ] }
check(identical(rta(2, 41914, 1)$roadTypeID, 4L), "f_system 2 urban, full control is road type 4")
check(identical(rta(2, 41914, 2)$roadTypeID, 5L), "f_system 2 urban, partial control is road type 5")
check(identical(rta(2, 41914, 3)$roadTypeID, 5L), "f_system 2 urban, no control is road type 5 (NY-13 case)")
check(identical(rta(2, 99999, 2)$roadTypeID, 3L), "f_system 2 rural, partial control is road type 3")
m2 = rta(2, 41914, NA_real_)
check(identical(m2$roadTypeID, 4L), "f_system 2 urban, access control missing is road type 4")
check(identical(rts(m2)$source, "default") && grepl("access control not coded; class 2 treated as restricted", rts(m2)$detail, fixed = TRUE),
      "class 2 without access control is a default")
check(identical(rts(rta(2, 41914, 3))$source, "derived") && grepl("access_control 3", rts(rta(2, 41914, 3))$detail), "class 2 coded is derived")
m1 = rta(1, 41914, NA_real_)
check(identical(m1$roadTypeID, 4L) && identical(rts(m1)$source, "derived"), "f_system 1, access control missing: restricted, no default row")
check(identical(rta(1, 99999, 3)$roadTypeID, 2L), "f_system 1 is restricted whatever access_control says")
m3 = rta(3, 99999, 1)
check(identical(m3$roadTypeID, 3L), "f_system 3 rural, full control stays unrestricted (road type 3)")
check(identical(rts(m3)$source, "derived") &&
        grepl("access control coded full on functional class 3; treated as unrestricted", rts(m3)$detail, fixed = TRUE), "class 3 full-control note")
check(identical(rta(4, 41914, 1)$roadTypeID, 5L), "f_system 4 urban, full control stays road type 5")
check(identical(rta(7, 41914, NA_real_)$roadTypeID, 5L), "f_system 7 urban, access control missing is road type 5")
check(identical(links_road_type(c(2, 2, 2, 3, 1), rep(1, 5), c(1, 3, NA, 1, NA)), c(4L, 5L, 4L, 5L, 4L)), "links_road_type vector form")
check(identical(links_road_type(2, 1), 4L), "links_road_type without access_control keeps the old rule")
# class 2: a coded section and an uncoded one do not merge; class 3 sections do
mix2 = function(f){ with_year(dplyr::bind_rows(dplyr::mutate(sec(begin_point = 0, end_point = 0.1, f_system = f), access_control = 1),
                                               dplyr::mutate(sec(begin_point = 0.1, end_point = 0.2, f_system = f), access_control = NA_real_))) }
check(nrow(links_build(mix2(2))) == 2, "class 2 coded and default road types are separate links")
check(nrow(links_build(mix2(3))) == 1, "class 3 sections merge whatever access_control says")

# 3. Merging ####

three = with_year(dplyr::bind_rows(sec(begin_point = 0, end_point = 0.1), sec(begin_point = 0.1, end_point = 0.25),
                                   sec(begin_point = 0.25, end_point = 0.4)))
L = links_build(three)
check(nrow(L) == 1, "three equal sections give one link")
check(near(L$linkLength, 0.4), "merged length is the sum")
check(identical(L$n_sections, 3L), "n_sections is 3")
check(near(L$begin_point, 0) && near(L$end_point, 0.4), "merged mileposts")
check(identical(L$direction, "one-way") && near(L$dir_share, 1), "one-way link has dir_share 1")
check(nrow(L$geometry[[1]]) == 4, "merged geometry binds the sections (shared joints once)")
check(identical(L$count_year, 2025), "count_year falls back to the layer year")
check(identical(L$linkDescription, "R1 0-0.4"), "description")

# shuffled input sorts first
L2 = links_build(with_year(three[c(3, 1, 2), ]))
check(nrow(L2) == 1 && near(L2$linkLength, 0.4), "unsorted sections still merge")

aadt_change = with_year(dplyr::bind_rows(sec(begin_point = 0, end_point = 0.1),
                                         sec(begin_point = 0.1, end_point = 0.2, aadt = 6000)))
check(nrow(links_build(aadt_change)) == 2, "a change of aadt starts a new link")

na_equal = with_year(dplyr::bind_rows(sec(begin_point = 0, end_point = 0.1, speed_limit = NA),
                                      sec(begin_point = 0.1, end_point = 0.2, speed_limit = NA)))
check(nrow(links_build(na_equal)) == 1, "NA equals NA when merging")

gap = with_year(dplyr::bind_rows(sec(begin_point = 0, end_point = 0.1), sec(begin_point = 0.2, end_point = 0.3)))
check(nrow(links_build(gap)) == 2, "a gap starts a new link")
tiny = with_year(dplyr::bind_rows(sec(begin_point = 0, end_point = 0.1), sec(begin_point = 0.1005, end_point = 0.2)))
check(nrow(links_build(tiny)) == 1, "a gap under 0.001 miles still joins")

long = with_year(dplyr::bind_rows(lapply(0:29, function(i){ sec(begin_point = i * 0.1, end_point = (i + 1) * 0.1) })))
Lg = links_build(long)
check(nrow(Lg) == 2, "the 2-mile stop splits 3 miles into two links")
check(all(Lg$linkLength <= 2 + 1e-9), "no merged link over 2 miles")
check(near(sum(Lg$linkLength), 3), "the 2-mile stop keeps all the miles")
check(identical(Lg$linkID, 1:2), "linkID 1..n")

# 4. Direction ####

two = links_build(with_year(sec(facility_type = 2, dir_factor = 60, data_year = 2024)))
check(nrow(two) == 2, "two-way section gives two links")
check(identical(two$direction, c("primary", "opposite")), "primary before opposite")
check(near(two$dir_share, c(0.6, 0.4)), "dir_share from dir_factor")
check(near(sum(two$dir_share), 1), "dir_share sums to 1")
check(identical(two$geometry[[2]], two$geometry[[1]][2:1, , drop = FALSE]), "opposite geometry reversed")
check(identical(two$linkDescription[2], "R1 0-0.1 opp"), "opposite description")
check(identical(two$count_year, c(2024, 2024)), "count_year from data_year")
check(identical(two$aadt, c(5000, 5000)), "aadt is both directions on each link")
half = links_build(with_year(sec(facility_type = 2, dir_factor = 30)))
check(near(half$dir_share, c(0.5, 0.5)), "dir_factor outside 50-100 gives half each way")
ramp = links_build(with_year(dplyr::bind_rows(sec(facility_type = 4), sec(route_id = "R2", facility_type = 5))))
check(identical(ramp$direction, c("one-way", "one-way")), "facility 4 and 5 are one-way")
fna = links_build(with_year(sec(facility_type = NA)))
check(nrow(fna) == 2, "facility NA is two-way")
s_fna = attr(fna, "sources")
check(any(s_fna$field == "direction" & s_fna$source == "default"), "facility NA has a default source row")

# 5. Uncounted and dropped ####

mix = with_year(dplyr::bind_rows(sec(), sec(route_id = "R2", aadt = NA), sec(route_id = "R3", aadt = 0,
                                 section_length = NA, begin_point = 1, end_point = 1.5),
                                 sec(route_id = "R4", facility_type = 6)))
Lm = links_build(mix)
check(nrow(Lm) == 1 && identical(Lm$route_id, "R1"), "only the counted inventory section is written")
u = attr(Lm, "uncounted")
check(is.data.frame(u) && sum(u$sections) == 2, "two sections uncounted")
check(near(sum(u$miles), 0.6), "uncounted miles fall back to end - begin")
check(all(c("roadTypeID", "f_system", "sections", "miles") %in% names(u)), "uncounted columns")
d = attr(Lm, "dropped")
check(is.data.frame(d) && sum(d$sections) == 1, "facility 6 dropped and counted")
check(all(grepl("second carriageway", d$reason)), "dropped reason")

# 6. Sources ####

s = attr(two, "sources")
check(all(c("linkID", "field", "value", "source", "detail", "data_year") %in% names(s)), "sources columns")
for(id in two$linkID){
  check(all(c("linkLength", "roadTypeID", "aadt", "dir_share") %in% s$field[s$linkID == id]),
        paste0("link ", id, " has its source rows"))
}
check(identical(s$source[s$field == "dir_share"], c("measured", "measured")), "dir_share measured from dir_factor")
check(all(attr(half, "sources")$source[attr(half, "sources")$field == "dir_share"] == "default"), "half each way is a default")
check(grepl("sum of 3 HPMS sections", attr(L, "sources")$detail[attr(L, "sources")$field == "linkLength"]), "length detail")

# 7. Empty input ####

e = links_build(with_year(sec()[0, ]))
check(nrow(e) == 0 && identical(names(e), LINKS_BUILD_COLS), "empty input gives empty frame with columns")

# 8. The 40-section fixture ####

txt = paste(readLines("moves_anywhere/tests/fixtures/links/hpms_ny2025_ithaca_box_40.geojson", warn = FALSE), collapse = "\n")
fx = links_parse_sections(txt)
attr(fx, "year") = 2025L
Lf = links_build(fx)
uf = attr(Lf, "uncounted")
cat("fixture: ", nrow(fx), " sections -> ", nrow(Lf), " links (", sum(Lf$direction != "opposite"),
    " before splitting by direction); uncounted ", sum(uf$sections), " sections, ",
    round(sum(uf$miles), 4), " miles\n", sep = "")
print(as.data.frame(Lf[, c("linkID", "route_id", "roadTypeID", "linkLength", "aadt", "direction", "n_sections")]))
check(nrow(Lf) == 15, "fixture gives 15 links")
check(sum(uf$sections) == 3, "fixture has 3 uncounted sections")
check(near(sum(Lf$linkLength[Lf$direction != "opposite"]),
           sum(fx$section_length[!is.na(fx$aadt) & fx$aadt > 0]), 1e-6), "fixture keeps every counted mile")

# the same 40 sections re-fetched with access_control (hpms_ny2025_ithaca_box_40_access.geojson)
txa = paste(readLines("moves_anywhere/tests/fixtures/links/hpms_ny2025_ithaca_box_40_access.geojson", warn = FALSE), collapse = "\n")
fa = links_parse_sections(txa)
attr(fa, "year") = 2025L
check(nrow(fa) == 40 && !anyNA(fa$access_control) && all(fa$access_control %in% 1:3), "access fixture has access_control on all 40")
La = links_build(fa)
both = merge(as.data.frame(Lf[, c("route_id", "begin_point", "end_point", "direction", "f_system", "roadTypeID")]),
             as.data.frame(La[, c("route_id", "begin_point", "direction", "roadTypeID")]),
             by = c("route_id", "begin_point", "direction"), suffixes = c("_old", "_new"), all = TRUE)
chg = both[!is.na(both$roadTypeID_old) & !is.na(both$roadTypeID_new) & both$roadTypeID_old != both$roadTypeID_new, ]
cat("access fixture: ", nrow(La), " links; ", nrow(chg), " of ", nrow(Lf), " links change road type\n", sep = "")
print(chg, row.names = FALSE)
src_rt = attr(La, "sources")[attr(La, "sources")$field == "roadTypeID", ]
check(all(src_rt$source == "derived"), "no fallback on the access fixture")
check(nrow(La) == nrow(Lf) && nrow(both) == nrow(Lf), "access fixture gives the same links")
check(nrow(chg) > 0 && all(chg$roadTypeID_old == 4 & chg$roadTypeID_new == 5), "changes are restricted to unrestricted (4 to 5)")

# 9. Result ####

if(length(failures) > 0){
  cat("FAIL\n", paste0("  ", failures, collapse = "\n"), "\n", sep = "")
  quit(status = 1)
}
cat("PASS\n")
