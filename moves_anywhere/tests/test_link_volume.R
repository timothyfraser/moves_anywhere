# test_link_volume.R ##########################################################
#
# What:      Offline test of the hourly link volume and the year factor (link_volume.R).
# Does:      Builds a small project run in a temp folder (runspec from inputs_project, literal county
#            tables, literal monthofanyyear and dayofanyweek through a fake get_table()) and checks
#            the flat-share identity, the hour share, the year factor, the direction split, the
#            K-factor cross-check row, empty input and remainder links.
# Called by: run by hand from the repository root: Rscript moves_anywhere/tests/test_link_volume.R
# Reads:     moves_anywhere/inputs_project/rs_custom.xml, moves_anywhere/scripts/*.R
# Writes:    a temp folder only (removed at the end)
# Exits:     0 and prints PASS, or prints what failed and exits 1
###############################################################################

suppressPackageStartupMessages({ library(dplyr); library(readr); library(tidyr); library(stringr) })
source("moves_anywhere/scripts/adapt_functions.R")
source("moves_anywhere/scripts/project_functions.R")
source("moves_anywhere/scripts/adapt_link.R")
source("moves_anywhere/scripts/link_volume.R")

# The default database is not available here: literal monthofanyyear and dayofanyweek.
# July is given 365/12 days so that the flat case is exact.
get_table = function(tablename){
  if(tablename == "monthofanyyear"){
    return(data.frame(monthID = 1:12, monthName = month.name, noOfDays = 365 / 12))
  }
  if(tablename == "dayofanyweek"){
    return(data.frame(dayID = c(2, 5), dayName = c("Weekend", "Weekdays"), noOfRealDays = c(2, 5)))
  }
  stop(paste0("test has no default table ", tablename))
}

failures = character(0)
check = function(ok, what){ if(!isTRUE(ok)){ failures <<- c(failures, what) } }
near = function(a, b, rel = 0.001){ isTRUE(all(abs(a - b) <= rel * abs(b))) }

# 1. A project run in a temp folder ####
root = tempfile("link_volume_")
dir.create(root)
rs = paste0(root, "/rs_custom.xml")
invisible(file.copy("moves_anywhere/inputs_project/rs_custom.xml", rs))
spec = project_spec(rs)                     # 2022, July, weekday, hour 8, road types 1 4 5
st = spec$sourcetypes
vmt_of = ifelse(st == 21, 3e6, ifelse(st == 62, 1e6, 0))

#' Write the county tables; hour8 is the hour 8 share for every vehicle and road type
new_bucket = function(hour8 = 1 / 24){
  B = tempfile("bucket_", tmpdir = root)
  dir.create(B)
  write_csv(data.frame(yearID = 2022, sourceTypeID = st, VMT = vmt_of), paste0(B, "/_sourcetypeyearvmt.csv"))
  write_csv(data.frame(sourceTypeID = st, monthID = 7, monthVMTFraction = 1 / 12), paste0(B, "/_monthvmtfraction.csv"))
  write_csv(expand.grid(sourceTypeID = st, monthID = 7, roadTypeID = c(4, 5), dayID = c(2, 5)) %>%
              mutate(dayVMTFraction = ifelse(dayID == 5, 5 / 7, 2 / 7)), paste0(B, "/_dayvmtfraction.csv"))
  write_csv(expand.grid(sourceTypeID = st, roadTypeID = c(4, 5), dayID = 5, hourID = 1:24) %>%
              mutate(hourVMTFraction = ifelse(hourID == 8, hour8, 1 / 24)), paste0(B, "/_hourvmtfraction.csv"))
  write_csv(expand.grid(sourceTypeID = st, roadTypeID = c(1, 4, 5)) %>%
              mutate(roadTypeVMTFraction = case_when(
                roadTypeID == 1 ~ 0,
                sourceTypeID == 21 & roadTypeID == 4 ~ 0.5, sourceTypeID == 21 & roadTypeID == 5 ~ 0.25,
                sourceTypeID == 62 & roadTypeID == 4 ~ 0.25, sourceTypeID == 62 & roadTypeID == 5 ~ 0.5,
                TRUE ~ 0)), paste0(B, "/_roadtypedistribution.csv"))
  B
}

#' Links as link_build.R makes them (only the contract's columns that matter here)
make_links = function(n = 1, aadt = 24000, dir_share = 1, roadTypeID = 4, count_year = 2022,
                      k_factor = NA_real_, direction = "one-way"){
  tibble(linkID = seq_len(n), route_id = "R1", begin_point = 0, end_point = 1,
         roadTypeID = roadTypeID, linkLength = 1, aadt = aadt, dir_share = dir_share,
         direction = direction, through_lanes = 2, speed_limit = 55,
         aadt_single_unit = NA_real_, aadt_combination = NA_real_, k_factor = k_factor,
         count_year = count_year, f_system = 3, urban_id = NA_real_, n_sections = 1,
         linkDescription = "test")
}
same_miles = function(year){ 1e6 }

# 2. Flat shares: the hourly volume is aadt / 24 ####
B = new_bucket()
out = links_volume(make_links(aadt = 24000), rs, B, spec = spec, vmt_year = same_miles)
check(near(out$linkVolume, 24000 / 24), paste0("flat shares give aadt/24 (got ", out$linkVolume, ")"))
check(out$year_factor == 1 && out$aadt_scaled == 24000, "same year gives factor 1")
s = attr(out, "sources")
check(all(c("linkVolume", "year_factor") %in% s$field), "sources has linkVolume and year_factor rows")
check(all(s$source[s$field %in% c("linkVolume", "year_factor")] == "derived"), "both rows are derived")
check(grepl("AADT 24000 x direction share 1 x year factor 1 (2022 to 2022)", s$detail[s$field == "linkVolume"], fixed = TRUE),
      paste0("linkVolume detail (got: ", s$detail[s$field == "linkVolume"], ")"))
check(!"peak_hour_check" %in% s$field, "no K-factor row without k_factor")
flat = out$linkVolume

# Road type 5 has a different mix but the same flat shares: same volume
out5 = links_volume(make_links(roadTypeID = 5), rs, B, spec = spec, vmt_year = same_miles)
check(near(out5$linkVolume, 1000), "flat shares give aadt/24 on road type 5")

# 3. Doubling the run hour's share doubles the volume ####
B2 = new_bucket(hour8 = 2 / 24)
out = links_volume(make_links(), rs, B2, spec = spec, vmt_year = same_miles)
check(near(out$linkVolume, 2 * flat), paste0("double hour share doubles volume (got ", out$linkVolume, ")"))

# 4. Year factor ####
spec30 = spec
spec30$year = 2030L
B3 = new_bucket()
write_csv(data.frame(yearID = 2030, sourceTypeID = st, VMT = vmt_of), paste0(B3, "/_sourcetypeyearvmt.csv"))
miles = function(year){ c(`2023` = 100, `2030` = 110)[[as.character(year)]] }
out = links_volume(make_links(count_year = 2023), rs, B3, spec = spec30, vmt_year = miles)
check(near(out$year_factor, 1.1, 1e-9), paste0("2023 to 2030 with miles 100 and 110 gives 1.1 (got ", out$year_factor, ")"))
check(near(out$aadt_scaled, 24000 * 1.1, 1e-9), "aadt_scaled = aadt x 1.1")
check(near(out$linkVolume, 1.1 * flat), "volume scales with the factor")
s = attr(out, "sources")
yf = s[s$field == "year_factor", ]
check(grepl("2023", yf$detail) && grepl("2030", yf$detail) && grepl("100", yf$detail) && grepl("110", yf$detail),
      paste0("year_factor detail names both years and both totals (got: ", yf$detail, ")"))

# Same year gives 1 without calling the lookup
out = links_volume(make_links(count_year = 2030), rs, B3, spec = spec30, vmt_year = function(y){ stop("not called") })
check(out$year_factor == 1, "same year gives 1 without a lookup")

# A failing lookup gives 1 and a default row
out = links_volume(make_links(count_year = 2019), rs, B3, spec = spec30,
                   vmt_year = function(y){ if(y == 2019) stop("no NEI miles for 2019") else 110 })
s = attr(out, "sources")
yf = s[s$field == "year_factor", ]
check(out$year_factor == 1, "failing lookup gives factor 1")
check(yf$source == "default" && grepl("no NEI miles for 2019", yf$detail, fixed = TRUE),
      paste0("failing lookup has a default row naming the problem (got: ", yf$source, " ", yf$detail, ")"))

# 5. Direction shares of one section sum to the one-way value ####
two = make_links(n = 2, dir_share = c(0.6, 0.4), direction = c("primary", "opposite"))
out = links_volume(two, rs, B, spec = spec, vmt_year = same_miles)
check(near(sum(out$linkVolume), flat), "0.6 and 0.4 links sum to the one-way value")
check(near(out$linkVolume[1], 0.6 * flat), "0.6 link carries 0.6 of the volume")

# 6. The K-factor row appears only when k_factor is present ####
kk = make_links(n = 2, dir_share = c(0.6, 0.4), direction = c("primary", "opposite"), k_factor = c(9, NA))
out = links_volume(kk, rs, B, spec = spec, vmt_year = same_miles)
s = attr(out, "sources")
pk = s[s$field == "peak_hour_check", ]
check(nrow(pk) == 1 && pk$linkID == 1, "one K-factor row, for the link with k_factor")
check(near(pk$value, 24000 * 0.6 * 9 / 100, 1e-9) && pk$source == "measured", "K-factor row value and source")
check(!"peak_hour_check" %in% names(out), "K factor is not a column of the links")

# 7. Empty input and remainder links ####
out = links_volume(make_links()[0, ], rs, B, spec = spec, vmt_year = same_miles)
check(nrow(out) == 0 && all(c("linkVolume", "year_factor", "aadt_scaled") %in% names(out)), "empty input gets the new columns")
rem = bind_rows(make_links(), make_links() %>% mutate(linkID = 2, direction = "remainder", linkVolume = 77))
out = links_volume(rem, rs, B, spec = spec, vmt_year = same_miles)
check(out$linkVolume[2] == 77 && near(out$linkVolume[1], flat), "remainder links are untouched")
check(!2 %in% attr(out, "sources")$linkID, "remainder links get no source rows")

# 8. The link's own mix ####
# Without mix: identical to today's (mix = NULL against an empty mix)
a0 = links_volume(make_links(n = 2, dir_share = c(0.6, 0.4), direction = c("primary", "opposite")),
                  rs, B2, spec = spec, vmt_year = same_miles)
a1 = links_volume(make_links(n = 2, dir_share = c(0.6, 0.4), direction = c("primary", "opposite")),
                  rs, B2, spec = spec, vmt_year = same_miles, mix = NULL)
check(identical(a0, a1), "mix = NULL gives the same result as no mix argument")
check(all(grepl("county default mix", attr(a0, "sources")$detail[attr(a0, "sources")$field == "linkVolume"])),
      "no mix: detail says county default mix")

# A link whose mix is all type 61 trucks takes type 61's hour share (hour 8 doubled for every type here,
# so give 61 its own hour share: 3 / 24)
if(61 %in% st){
  B4 = new_bucket()
  hv = read_csv(paste0(B4, "/_hourvmtfraction.csv"), show_col_types = FALSE) %>%
    mutate(hourVMTFraction = ifelse(hourID == 8 & sourceTypeID == 61, 3 / 24, hourVMTFraction))
  write_csv(hv, paste0(B4, "/_hourvmtfraction.csv"))
  mx = tibble(linkID = 1, sourceTypeID = 61, sourceTypeHourFraction = 1)
  base = links_volume(make_links(n = 2), rs, B4, spec = spec, vmt_year = same_miles)
  own = links_volume(make_links(n = 2), rs, B4, spec = spec, vmt_year = same_miles, mix = mx)
  check(near(own$linkVolume[1], 3 * 1000), paste0("all-61 mix takes type 61's hour share (got ", own$linkVolume[1], ")"))
  check(own$linkVolume[2] == base$linkVolume[2], "link without mix rows keeps the default mix")
  so = attr(own, "sources"); so = so[so$field == "linkVolume", ]
  check(grepl("link's truck-count mix", so$detail[1], fixed = TRUE) && grepl("county default mix", so$detail[2], fixed = TRUE),
        "source detail names the mix used")
  # Shares not summing to 1 are renormalised, with a default row
  mx2 = tibble(linkID = 1, sourceTypeID = 61, sourceTypeHourFraction = 0.5)
  own2 = links_volume(make_links(n = 2), rs, B4, spec = spec, vmt_year = same_miles, mix = mx2)
  check(near(own2$linkVolume[1], 3000), "mix summing to 0.5 is renormalised")
  s2 = attr(own2, "sources")
  check(any(s2$linkID == 1 & s2$source == "default" & grepl("renormalised", s2$detail)), "renormalisation has a default row")
}else{
  failures = c(failures, "test run lacks source type 61")
}

# 9. Result ####
unlink(root, recursive = TRUE)
if(length(failures) > 0){
  cat("FAIL\n", paste0("- ", failures, collapse = "\n"), "\n")
  quit(status = 1)
}
cat("PASS: test_link_volume.R\n")
