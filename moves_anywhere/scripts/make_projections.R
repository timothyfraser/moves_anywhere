# make_projections.R ##########################################################
#
# What:      Script to summarize how projections.rds gets made
# Does:      Joins catr::projections to 2022 county land area and computes each county's
#            population density and its share of all counties' density by year.
# Called by: Developer tool: shows how projections.rds was made. Not part of a run; launch.sh does not run it.
# Reads:     catr::projections; county boundaries from tigris (2022)
# Writes:    scripts/projections.rds
# Needs:     dplyr, readr, tigris, sf, catr
###############################################################################

library(dplyr)
library(readr)
library(tigris)
library(sf)

# Get me the land area of these counties
area = tigris::counties(cb = TRUE, year = 2022) %>%
  select(geoid = GEOID, name = NAME, state = STUSPS, area_land = ALAND, geometry) %>%
  mutate(area_land = area_land / (1e3^2) )

# Calculate each county's population density.
stat = catr::projections %>%
  left_join(
    by = "geoid",
    y = area %>%
      as_tibble() %>%
      select(geoid, area_land)) %>%
  mutate(density = pop / area_land) %>%
  group_by(year) %>%
  mutate(fraction2 = density / sum(density, na.rm = TRUE)) %>%
  ungroup()

stat %>% saveRDS("scripts/projections.rds")

