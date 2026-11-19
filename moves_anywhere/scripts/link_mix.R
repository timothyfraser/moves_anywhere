# link_mix.R ###################################################################
#
# What:      vehicle mix of project-scale links from federal truck counts (HPMS)
# Does:      links_mix gives each link that has both truck counts (aadt_single_unit and
#            aadt_combination) a vehicle mix: the single-unit share goes to source types 52, 53 and 54,
#            the combination share to 61 and 62, each split in proportion to the county default mix of
#            the link's road type; everything else goes to the other vehicle types in proportion to the
#            default mix with those five types removed. Links without both counts get no rows, so the
#            project adapter's default mix applies to them.
#            Simplification: HPMS "single-unit" counts include buses (FHWA classes 4 to 7), but buses
#            (types 41, 42, 43) stay in the remainder here, so the truck share is a little high and the
#            bus share a little low.
# Called by: task_links.R (the links command)
# Reads:     the links data frame (columns linkID, roadTypeID, aadt, aadt_single_unit,
#            aadt_combination, direction; optional count_year); the county tables through
#            link_default_mix() (adapt_link.R) and project_spec() (project_functions.R)
# Writes:    nothing; returns the rows of linksourcetypehour.csv with attribute "sources"
# Needs:     adapt_link.R (link_default_mix) and project_functions.R (project_spec); dplyr
###############################################################################

# 1. Shares of one link ####

#' Split one link's mix over the run's vehicle types
#' @param su single-unit truck share of the link's count (0 to 1)
#' @param cu combination truck share of the link's count (0 to 1)
#' @param w default weights (named by sourceTypeID) of the run's vehicle types on the link's road type
#' @return named numeric vector of shares over names(w), summing to 1 (6 decimals)
link_mix_shares = function(su, cu, w){
  types = as.numeric(names(w))
  groups = list(su = c(52, 53, 54), cu = c(61, 62))
  trucks = unlist(groups)
  inrun = lapply(groups, function(g) g[g %in% types])
  rest = types[!types %in% trucks]

  # Within a group: in proportion to the default mix, equally if the group's default shares are all zero
  split = function(share, ids){
    out = setNames(rep(0, length(ids)), ids)
    if(length(ids) == 0){ return(out) }
    v = w[as.character(ids)]
    out[] = if(sum(v) > 0) share * v / sum(v) else share / length(ids)
    out
  }

  shares = setNames(rep(0, length(types)), types)
  # A truck group with no type in the run adds its share to the remainder
  rem = 1 - (if(length(inrun$su) > 0) su else 0) - (if(length(inrun$cu) > 0) cu else 0)
  shares[as.character(inrun$su)] = split(su, inrun$su)
  shares[as.character(inrun$cu)] = split(cu, inrun$cu)
  if(length(rest) > 0){
    shares[as.character(rest)] = split(rem, rest)
  }else if(sum(shares) > 0){
    shares = shares / sum(shares)          # no other type in the run: the truck types carry everything
  }

  # Renormalise, round to 6 decimals, put the rounding error on the largest share
  shares = shares / sum(shares)
  shares = round(shares, 6)
  big = which.max(shares)
  shares[big] = round(shares[big] + (1 - sum(shares)), 6)
  shares
}

# 2. The vehicle mix ####

#' Vehicle mix from truck counts
#' @param links data frame, one row per link (see the link table contract)
#' @param .runspec path to the run's runspec (XML)
#' @param BUCKET inputs folder (the county tables are read from it)
#' @param spec result of project_spec(), or NULL to read it from .runspec
#' @return tibble linkID, sourceTypeID, sourceTypeHourFraction for links with both truck counts (zero rows
#'   if none); attribute "sources": linkID, field, value, source, detail, data_year
links_mix = function(links, .runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs", spec = NULL){
  if(is.null(spec)){ spec = project_spec(.runspec) }
  out = dplyr::tibble(linkID = numeric(0), sourceTypeID = numeric(0), sourceTypeHourFraction = numeric(0))
  src = dplyr::tibble(linkID = numeric(0), field = character(0), value = numeric(0),
                      source = character(0), detail = character(0), data_year = numeric(0))

  if("direction" %in% names(links)){ links = links[is.na(links$direction) | links$direction != "remainder", ] }
  year = if("count_year" %in% names(links)) suppressWarnings(as.numeric(links$count_year)) else rep(NA_real_, nrow(links))
  su_n = suppressWarnings(as.numeric(links$aadt_single_unit))
  cu_n = suppressWarnings(as.numeric(links$aadt_combination))
  total = suppressWarnings(as.numeric(links$aadt))

  has = !is.na(su_n) & !is.na(cu_n) & !is.na(total) & total > 0 & su_n >= 0 & cu_n >= 0
  too_many = has & (su_n + cu_n > total + 1e-9)
  ok = has & !too_many

  if(any(too_many)){
    src = dplyr::bind_rows(src, dplyr::tibble(
      linkID = links$linkID[too_many], field = "vehicle mix", value = NA_real_, source = "default",
      detail = "truck counts exceed the total count; default mix used", data_year = year[too_many]))
  }
  if(any(ok)){
    road = links[ok, ]
    mix = link_default_mix(road$roadTypeID, spec, BUCKET, .runspec)
    rows = vector("list", nrow(road))
    for(i in seq_len(nrow(road))){
      m = mix[mix$roadTypeID == road$roadTypeID[i], ]
      w = setNames(m$share, m$sourceTypeID)
      su = su_n[ok][i] / total[ok][i]
      cu = cu_n[ok][i] / total[ok][i]
      s = link_mix_shares(su, cu, w)
      rows[[i]] = dplyr::tibble(linkID = road$linkID[i], sourceTypeID = as.numeric(names(s)),
                                sourceTypeHourFraction = as.numeric(s))
      src = dplyr::bind_rows(src, dplyr::tibble(
        linkID = road$linkID[i], field = "vehicle mix", value = round((su + cu) * 100, 1), source = "derived",
        detail = paste0("single-unit ", sprintf("%.1f", su * 100), "% and combination ", sprintf("%.1f", cu * 100),
                        "% from federal truck counts; other types by the county default. ",
                        "Buses are kept in the remainder (HPMS single-unit counts include buses)"),
        data_year = year[ok][i]))
    }
    out = dplyr::bind_rows(rows)
    out = out[order(out$linkID, out$sourceTypeID), ]
  }
  attr(out, "sources") = src
  out
}
