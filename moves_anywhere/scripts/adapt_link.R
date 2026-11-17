# adapt_link.R ################################################################
#
# What:      adapt the project-scale link tables
# Does:      adapt_link checks the user's link.csv and fills blanks (county, zone, grade, description,
#            and the average speed of a road link). adapt_linksourcetypehour gives each road link its
#            vehicle mix: the user's rows, else a default built from the county tables.
#            adapt_driveschedulesecondlink checks and passes on the user's drive schedules.
#            Every default that is used is recorded with project_note().
# Called by: task_adapt.R, step 6 of launch.sh (project runs only, after the county adapters)
# Reads:     EPA_MOVES_Model/rs_custom.xml (runspec); inputs/link.csv, inputs/linksourcetypehour.csv,
#            inputs/driveschedulesecondlink.csv; the county tables inputs/_sourcetypeyearvmt.csv,
#            _monthvmtfraction.csv, _dayvmtfraction.csv, _hourvmtfraction.csv, _roadtypedistribution.csv,
#            _avgspeeddistribution.csv (through project_read); the default avgspeedbin table
# Writes:    inputs/_link.csv, inputs/_linksourcetypehour.csv, inputs/_driveschedulesecondlink.csv,
#            and rows in inputs/_project_inputs.csv (project_note)
# Needs:     adapt_functions.R (get_changes, get_is_custom, get_data, import_table) and
#            project_functions.R (project_spec, project_read, project_note); dplyr, readr
###############################################################################

# 1. Small helpers ####

#' Convert a column to numbers; stop on text that is not a number
#' @param x the column
#' @param what name of the column, for the message
#' @param ids linkID of each row, for the message
link_num = function(x, what, ids){
  out = suppressWarnings(as.numeric(x))
  bad = which(!is.na(x) & trimws(as.character(x)) != "" & is.na(out))
  if(length(bad) > 0){ stop(paste0("link ", ids[bad[1]], " ", what, " is not a number")) }
  out
}

#' Stop unless a data frame has the columns (names already lower case)
#' @param data data frame
#' @param needed lower-case column names
#' @param file name of the user's file, for the message
#' @param spelling MOVES spelling of the names, same order as needed
link_need = function(data, needed, file, spelling){
  missing = which(!needed %in% names(data))
  if(length(missing) > 0){ stop(paste0(file, " needs column ", spelling[missing[1]])) }
}

#' Read one of the user's link files, or NULL if the user did not give it
#' @param table table name in lower case, for example "linksourcetypehour"
#' @param BUCKET inputs folder
link_user = function(table, BUCKET = "inputs"){
  f = get_is_custom(get_changes(BUCKET), table = table)
  if(!f$is_custom){ return(NULL) }
  get_data(changes = f$changes)
}

#' The user's linksourcetypehour.csv with MOVES spelling, or NULL
#' @param BUCKET inputs folder
link_user_mix = function(BUCKET = "inputs"){
  data = link_user("linksourcetypehour", BUCKET)
  if(is.null(data)){ return(NULL) }
  link_need(data, c("linkid", "sourcetypeid", "sourcetypehourfraction"), "linksourcetypehour.csv",
            c("linkID", "sourceTypeID", "sourceTypeHourFraction"))
  dplyr::tibble(
    linkID = suppressWarnings(as.numeric(data$linkid)),
    sourceTypeID = suppressWarnings(as.numeric(data$sourcetypeid)),
    sourceTypeHourFraction = suppressWarnings(as.numeric(data$sourcetypehourfraction)))
}

# 2. The default vehicle mix and speed ####

#' Default vehicle mix by road type
#' @param roadtypes road types that need a default
#' @param spec result of project_spec()
#' @param BUCKET inputs folder
#' @param .runspec path to the run's runspec (XML)
#' @return tibble roadTypeID, sourceTypeID, share; one row per road type and run vehicle type (zeros kept)
link_default_mix = function(roadtypes, spec, BUCKET = "inputs", .runspec = "EPA_MOVES_Model/rs_custom.xml"){
  vmt = tryCatch(
    project_read("sourcetypeyearvmt", .runspec, BUCKET, default = FALSE, spec = spec),
    error = function(e){ stop("default vehicle mix needs sourcetypeyearvmt; give linksourcetypehour.csv") })
  month = project_read("monthvmtfraction", .runspec, BUCKET, spec = spec)
  day = project_read("dayvmtfraction", .runspec, BUCKET, spec = spec)
  hour = project_read("hourvmtfraction", .runspec, BUCKET, spec = spec)
  road = project_read("roadtypedistribution", .runspec, BUCKET, spec = spec)

  grid = expand.grid(roadTypeID = sort(unique(roadtypes)), sourceTypeID = spec$sourcetypes)
  w = grid %>%
    dplyr::left_join(by = "sourceTypeID", y = vmt %>%
      dplyr::select(sourceTypeID = sourcetypeid, vmt) %>% dplyr::distinct()) %>%
    dplyr::left_join(by = "sourceTypeID", y = month %>%
      dplyr::select(sourceTypeID = sourcetypeid, monthvmtfraction) %>% dplyr::distinct()) %>%
    dplyr::left_join(by = c("sourceTypeID", "roadTypeID"), y = day %>%
      dplyr::select(sourceTypeID = sourcetypeid, roadTypeID = roadtypeid, dayvmtfraction) %>% dplyr::distinct()) %>%
    dplyr::left_join(by = c("sourceTypeID", "roadTypeID"), y = hour %>%
      dplyr::select(sourceTypeID = sourcetypeid, roadTypeID = roadtypeid, hourvmtfraction) %>% dplyr::distinct()) %>%
    dplyr::left_join(by = c("sourceTypeID", "roadTypeID"), y = road %>%
      dplyr::select(sourceTypeID = sourcetypeid, roadTypeID = roadtypeid, roadtypevmtfraction) %>% dplyr::distinct()) %>%
    dplyr::mutate(
      weight = vmt * monthvmtfraction * dayvmtfraction * hourvmtfraction * roadtypevmtfraction,
      weight = ifelse(is.na(weight), 0, weight))

  total = tapply(w$weight, w$roadTypeID, sum)
  for(r in names(total)){
    if(total[[r]] <= 0){ stop(paste0("no default vehicle mix for road type ", r, "; give linksourcetypehour.csv")) }
  }
  w$share = w$weight / as.numeric(total[as.character(w$roadTypeID)])
  dplyr::as_tibble(w[order(w$roadTypeID, w$sourceTypeID), c("roadTypeID", "sourceTypeID", "share")])
}

#' Vehicle mix of each road link: the user's rows where given, else the default
#' @param links data frame with linkID and roadTypeID (the off-network link, roadTypeID 1, gets no rows)
#' @param user result of link_user_mix(), or NULL
#' @param spec result of project_spec()
#' @param BUCKET inputs folder
#' @param .runspec path to the run's runspec (XML)
#' @return tibble linkID, sourceTypeID, sourceTypeHourFraction, source ("user" or "default")
link_mix = function(links, user, spec, BUCKET = "inputs", .runspec = "EPA_MOVES_Model/rs_custom.xml"){
  roads = links[links$roadTypeID != 1, ]
  covered = if(is.null(user)) numeric(0) else unique(user$linkID)
  from_user = roads[roads$linkID %in% covered, ]
  from_default = roads[!roads$linkID %in% covered, ]

  out = dplyr::tibble(linkID = numeric(0), sourceTypeID = numeric(0),
                      sourceTypeHourFraction = numeric(0), source = character(0))
  if(nrow(from_user) > 0){
    out = dplyr::bind_rows(out, user[user$linkID %in% from_user$linkID, ] %>% dplyr::mutate(source = "user"))
  }
  if(nrow(from_default) > 0){
    mix = link_default_mix(from_default$roadTypeID, spec, BUCKET, .runspec)
    d = from_default %>%
      dplyr::select(linkID, roadTypeID) %>%
      dplyr::inner_join(by = "roadTypeID", y = mix, relationship = "many-to-many") %>%
      dplyr::transmute(linkID, sourceTypeID, sourceTypeHourFraction = share, source = "default")
    out = dplyr::bind_rows(out, d)
  }
  out[order(out$linkID, out$sourceTypeID), ]
}

#' Default average speed of links, from their vehicle mix (harmonic: miles divided by hours)
#' @param mix result of link_mix() for the links of interest
#' @param links data frame with linkID and roadTypeID
#' @param spec result of project_spec()
#' @param BUCKET inputs folder
#' @param .runspec path to the run's runspec (XML)
#' @return tibble linkID, speed
link_default_speed = function(mix, links, spec, BUCKET = "inputs", .runspec = "EPA_MOVES_Model/rs_custom.xml"){
  ads = project_read("avgspeeddistribution", .runspec, BUCKET, spec = spec)
  bins = project_read("avgspeedbin", .runspec, BUCKET, spec = spec)
  v = ads %>%
    dplyr::inner_join(by = "avgspeedbinid", y = bins %>% dplyr::select(avgspeedbinid, avgbinspeed)) %>%
    dplyr::group_by(sourceTypeID = sourcetypeid, roadTypeID = roadtypeid) %>%
    dplyr::summarise(v = sum(avgspeedfraction * avgbinspeed), .groups = "drop")

  out = dplyr::tibble(linkID = numeric(0), speed = numeric(0))
  for(id in unique(mix$linkID)){
    m = mix[mix$linkID == id & mix$sourceTypeHourFraction > 0, ]
    m$roadTypeID = links$roadTypeID[links$linkID == id][1]
    m = dplyr::inner_join(m, v, by = c("sourceTypeID", "roadTypeID"))
    m = m[m$v > 0, ]
    if(nrow(m) == 0){ stop(paste0("no default speed for link ", id, "; give linkAvgSpeed")) }
    speed = sum(m$sourceTypeHourFraction) / sum(m$sourceTypeHourFraction / m$v)
    out = dplyr::bind_rows(out, dplyr::tibble(linkID = id, speed = speed))
  }
  out
}

# 3. The link table ####

#' Adapt the link table
#' @param .runspec path to the run's runspec (XML)
#' @param BUCKET inputs folder
adapt_link = function(.runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs"){
  spec = project_spec(.runspec)
  geoid = spec$geoid[1]

  data = link_user("link", BUCKET)
  if(is.null(data)){ stop("link.csv is missing from the inputs folder") }
  link_need(data, c("linkid", "roadtypeid", "linklength", "linkvolume"), "link.csv",
            c("linkID", "roadTypeID", "linkLength", "linkVolume"))
  if(nrow(data) == 0){ stop("link.csv has no rows") }

  # Link numbers
  id = suppressWarnings(as.numeric(data$linkid))
  bad = which(is.na(id) | id < 1 | id != round(id))
  if(length(bad) > 0){ stop(paste0("linkID ", data$linkid[bad[1]], " is not a positive whole number")) }
  dup = id[duplicated(id)]
  if(length(dup) > 0){ stop(paste0("linkID ", dup[1], " is repeated")) }

  # Road types
  road = suppressWarnings(as.numeric(data$roadtypeid))
  bad = which(is.na(road) | !road %in% spec$roadtypes)
  if(length(bad) > 0){ stop(paste0("link ", id[bad[1]], " roadTypeID ", data$roadtypeid[bad[1]], " is not in the runspec")) }
  if(sum(road == 1) > 1){ stop("more than one link has roadTypeID 1 (off-network)") }
  is_road = road != 1

  # Numbers
  len = link_num(data$linklength, "linkLength", id)
  vol = link_num(data$linkvolume, "linkVolume", id)
  speed = if("linkavgspeed" %in% names(data)) link_num(data$linkavgspeed, "linkAvgSpeed", id) else rep(NA_real_, nrow(data))
  grade = if("linkavggrade" %in% names(data)) link_num(data$linkavggrade, "linkAvgGrade", id) else rep(NA_real_, nrow(data))
  bad = which(len < 0)
  if(length(bad) > 0){ stop(paste0("link ", id[bad[1]], " has a negative linkLength")) }
  bad = which(vol < 0)
  if(length(bad) > 0){ stop(paste0("link ", id[bad[1]], " has a negative linkVolume")) }
  bad = which(speed < 0)
  if(length(bad) > 0){ stop(paste0("link ", id[bad[1]], " has a negative linkAvgSpeed")) }

  # County and zone, if given
  county = if("countyid" %in% names(data)) link_num(data$countyid, "countyID", id) else rep(NA_real_, nrow(data))
  zone = if("zoneid" %in% names(data)) link_num(data$zoneid, "zoneID", id) else rep(NA_real_, nrow(data))
  bad = which(!is.na(county) & county != geoid)
  if(length(bad) > 0){ stop(paste0("link ", id[bad[1]], " countyID ", county[bad[1]], " is not ", geoid)) }
  bad = which(!is.na(zone) & zone != geoid * 10)
  if(length(bad) > 0){ stop(paste0("link ", id[bad[1]], " zoneID ", zone[bad[1]], " is not ", geoid * 10)) }

  # Road links need a length and a volume
  bad = which(is_road & is.na(len))
  if(length(bad) > 0){ stop(paste0("link ", id[bad[1]], " has no linkLength")) }
  bad = which(is_road & is.na(vol))
  if(length(bad) > 0){ stop(paste0("link ", id[bad[1]], " has no linkVolume")) }

  # Fills
  used_default = any(is.na(county)) || any(is.na(zone)) || any(is.na(grade))
  county[is.na(county)] = geoid
  zone[is.na(zone)] = geoid * 10
  grade[is.na(grade)] = 0
  desc = if("linkdescription" %in% names(data)) as.character(data$linkdescription) else rep("", nrow(data))
  desc[is.na(desc)] = ""
  desc = substr(desc, 1, 50)
  len[!is_road & is.na(len)] = 0
  vol[!is_road & is.na(vol)] = 0
  speed[!is_road & is.na(speed)] = 0

  # Blank speeds on road links: the drive schedule's mean, else the default speed
  need = which(is.na(speed))
  if(length(need) > 0){
    used_default = TRUE
    sched = link_user("driveschedulesecondlink", BUCKET)
    from_sched = rep(FALSE, length(need))
    if(!is.null(sched)){
      link_need(sched, c("linkid", "secondid", "speed"), "driveschedulesecondlink.csv",
                c("linkID", "secondID", "speed"))
      for(k in seq_along(need)){
        s = suppressWarnings(as.numeric(sched$speed[as.numeric(sched$linkid) == id[need[k]]]))
        if(length(s) > 0){
          speed[need[k]] = round(mean(s, na.rm = TRUE), 2)
          from_sched[k] = TRUE
        }
      }
    }
    todo = need[!from_sched]
    if(length(todo) > 0){
      links = dplyr::tibble(linkID = id[todo], roadTypeID = road[todo])
      mix = link_mix(links, link_user_mix(BUCKET), spec, BUCKET, .runspec)
      d = link_default_speed(mix, links, spec, BUCKET, .runspec)
      speed[todo] = round(d$speed[match(id[todo], d$linkID)], 2)
    }
    for(k in seq_along(need)){
      project_note(item = paste0("link ", id[need[k]], " linkAvgSpeed"), source = "default",
                   detail = paste0(speed[need[k]], " mph from ",
                                   ifelse(from_sched[k], "its drive schedule", "avgspeeddistribution")),
                   BUCKET = BUCKET)
    }
  }

  # Write
  out = dplyr::tibble(linkID = id, countyID = county, zoneID = zone, roadTypeID = road,
                      linkLength = len, linkVolume = vol, linkAvgSpeed = speed,
                      linkDescription = desc, linkAvgGrade = grade)
  out = out[order(out$linkID), ]
  import_table(data = out, tablename = "link", adapt = used_default, save = TRUE, volume = BUCKET)
}

# 4. The vehicle mix ####

#' Adapt the linksourcetypehour table
#' @param .runspec path to the run's runspec (XML)
#' @param BUCKET inputs folder
adapt_linksourcetypehour = function(.runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs"){
  spec = project_spec(.runspec)
  links = readr::read_csv(paste0(BUCKET, "/_link.csv"), show_col_types = FALSE, progress = FALSE)
  user = link_user_mix(BUCKET)

  if(!is.null(user)){
    bad = which(!user$linkID %in% links$linkID)
    if(length(bad) > 0){ stop(paste0("linksourcetypehour.csv has link ", user$linkID[bad[1]], " not in link.csv")) }
    off = links$linkID[links$roadTypeID == 1]
    bad = which(user$linkID %in% off)
    if(length(bad) > 0){ stop(paste0("linksourcetypehour.csv has rows for off-network link ", user$linkID[bad[1]])) }
    bad = which(!user$sourceTypeID %in% spec$sourcetypes)
    if(length(bad) > 0){ stop(paste0("linksourcetypehour.csv has sourceTypeID ", user$sourceTypeID[bad[1]], " not in the runspec")) }
    sums = tapply(user$sourceTypeHourFraction, user$linkID, sum)
    for(l in names(sums)){
      if(is.na(sums[[l]]) || abs(sums[[l]] - 1) > 0.0001){
        stop(paste0("vehicle mix for link ", l, " sums to ", round(sums[[l]], 4), ", not 1"))
      }
    }
  }

  mix = link_mix(links[, c("linkID", "roadTypeID")], user, spec, BUCKET, .runspec)
  out = mix[, c("linkID", "sourceTypeID", "sourceTypeHourFraction")]

  made = unique(mix$linkID[mix$source == "default"])
  given = unique(mix$linkID[mix$source == "user"])
  if(length(made) > 0){
    project_note(item = paste0("vehicle mix, links ", paste(made, collapse = ", ")), source = "default",
                 detail = "sourcetypeyearvmt x month, day, hour and road type shares", BUCKET = BUCKET)
  }
  if(length(given) > 0){
    project_note(item = paste0("vehicle mix, links ", paste(given, collapse = ", ")), source = "user",
                 detail = "linksourcetypehour.csv", BUCKET = BUCKET)
  }
  import_table(data = out, tablename = "linksourcetypehour", adapt = length(made) > 0, save = TRUE, volume = BUCKET)
}

# 5. Drive schedules ####

#' Adapt the driveschedulesecondlink table (nothing is written if the user gave none)
#' @param .runspec path to the run's runspec (XML)
#' @param BUCKET inputs folder
adapt_driveschedulesecondlink = function(.runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs"){
  data = link_user("driveschedulesecondlink", BUCKET)
  if(is.null(data)){ return(invisible(NULL)) }
  link_need(data, c("linkid", "secondid", "speed"), "driveschedulesecondlink.csv",
            c("linkID", "secondID", "speed"))
  links = readr::read_csv(paste0(BUCKET, "/_link.csv"), show_col_types = FALSE, progress = FALSE)

  id = suppressWarnings(as.numeric(data$linkid))
  second = suppressWarnings(as.numeric(data$secondid))
  speed = suppressWarnings(as.numeric(data$speed))
  grade = if("grade" %in% names(data)) suppressWarnings(as.numeric(data$grade)) else rep(NA_real_, nrow(data))

  bad = which(is.na(id) | !id %in% links$linkID)
  if(length(bad) > 0){ stop(paste0("driveschedulesecondlink.csv has link ", data$linkid[bad[1]], " not in link.csv")) }
  bad = which(id %in% links$linkID[links$roadTypeID == 1])
  if(length(bad) > 0){ stop(paste0("driveschedulesecondlink.csv has rows for off-network link ", id[bad[1]])) }
  bad = which(is.na(second) | second < 1 | second != round(second))
  if(length(bad) > 0){ stop(paste0("link ", id[bad[1]], " secondID ", data$secondid[bad[1]], " is not a positive whole number")) }
  dup = which(duplicated(paste(id, second)))
  if(length(dup) > 0){ stop(paste0("link ", id[dup[1]], " repeats secondID ", second[dup[1]])) }
  bad = which(is.na(speed))
  if(length(bad) > 0){ stop(paste0("link ", id[bad[1]], " second ", second[bad[1]], " has no speed")) }
  bad = which(speed < 0)
  if(length(bad) > 0){ stop(paste0("link ", id[bad[1]], " second ", second[bad[1]], " has a negative speed")) }
  grade[is.na(grade)] = 0

  out = dplyr::tibble(linkID = id, secondID = second, speed = speed, grade = grade)
  out = out[order(out$linkID, out$secondID), ]
  import_table(data = out, tablename = "driveschedulesecondlink", adapt = FALSE, save = TRUE, volume = BUCKET)
}
