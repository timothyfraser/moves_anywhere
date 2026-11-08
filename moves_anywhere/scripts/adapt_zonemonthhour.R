# adapt_zonemonthhour.R #######################################################
#
# What:      Adapter for the zonemonthhour input table (temperature and relative humidity).
# Does:      Imports the user's zonemonthhour CSV if supplied; otherwise filters the default
#            zonemonthhour table to the county's zones and the runspec's months and hours.
# Called by: task_adapt.R, step 6 of launch.sh
# Reads:     the runspec; the zonemonthhour CSV in inputs/, if supplied; otherwise tables
#            zone and zonemonthhour in the custom input database
# Writes:    inputs/_zonemonthhour.csv (via import_table)
# Needs:     adapt_functions.R (get_changes, get_is_custom, get_data, import_table),
#            sourced by task_adapt.R; catr (translate_rs); dplyr, stringr, tidyr, DBI;
#            catr (connect)
###############################################################################

#' Adapt the zonemonthhour table
#' @param .runspec path to the run's runspec (XML)
adapt_zonemonthhour = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  
  ### zonemonthhour ################################
  table = "zonemonthhour"
  BUCKET = "inputs"
  
  # Get your list of key values from your runspec
  rs = catr::translate_rs(.runspec = .runspec)
  # Get name of custom input database
  .custom = rs$defaultdbname
  .year =  rs$year # eg. 1:12,
  .month = rs$month # eg. 1:12,
  .hour = rs$hour # eg. 1:24,
  .day = rs$day  # eg. c(2,5)
  .hourday = tidyr::expand_grid(hour = .hour, day = .day) %>%
    mutate(hourday = paste0(hour, day)) %>% with(hourday)
  .geoid = rs$geoid
  .geoidchar = stringr::str_pad(.geoid, width = 5, side = "left", pad = "0")
  
  # Get files for my bucket
  files = get_changes(BUCKET)
  
  # Classify that table as valid or not
  f = get_is_custom(files, table = table)   
  
  
  if(!table %in% files$changed){
    
    custom = connect("mariadb", .custom)
    # Download and filter the table
    ids = custom %>% tbl("zone") %>% filter(countyID %in% !!.geoid) %>% select(zoneID) %>% distinct() %>% collect()
    # Download and filter the table
    data = custom %>% tbl("zonemonthhour") %>% 
      filter(
        zoneID %in% !!ids$zoneID,
        monthID %in% !!.month, 
        hourID %in% !!.hour
      ) %>% 
      collect()
    dbDisconnect(custom)
    # Import table!
    import_table(data = data, tablename = table, .custom = .custom, adapt = TRUE, save = TRUE, volume = BUCKET)
    # IF CUSTOMIZED
  }else if(table %in% files$changed){
    # Classify that table as valid or not
    f = get_is_custom(files, table = table)
    # Load data from file
    data = get_data(changes = f$changes, .geoidchar = .geoidchar)
    # get_names(table = "zonemonthhour")
    data = data %>% 
      select(
        "monthID" = "monthid",
        "zoneID" = "zoneid",
        "hourID" = "hourid",
        "temperature" = "temperature",
        "relHumidity" = "relhumidity"
      )
    # These values are used during MOVES runtime only - so you don't fill them in.
    # "heatIndex" = "heatindex",
    # "specificHumidity" = "specifichumidity",
    # "molWaterFraction" = "molwaterfraction"
    
    # Import the table
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = FALSE, save = TRUE, volume = BUCKET)
  }
  
}