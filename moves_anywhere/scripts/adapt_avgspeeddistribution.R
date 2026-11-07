# adapt_avgspeeddistribution.R ################################################
#
# What:      Adapts the avgspeeddistribution input table for the run.
# Does:      Uses inputs/avgspeeddistribution.csv if provided; otherwise takes the default
#            table, filtered to the runspec's hour-days.
# Called by: task_adapt.R, step 6 of launch.sh
# Reads:     EPA_MOVES_Model/rs_custom.xml (the runspec)
#            inputs/avgspeeddistribution.csv (optional)
#            table avgspeeddistribution in the default input database
# Writes:    inputs/_avgspeeddistribution.csv
# Needs:     adapt_functions.R (get_changes, get_is_custom, get_data, import_table)
#            catr, dplyr, tidyr, stringr, DBI, RMariaDB
###############################################################################

#' Adapt the avgspeeddistribution table
#' @param .runspec path to the run's runspec (XML)
adapt_avgspeeddistribution = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  
  table = "avgspeeddistribution"
  BUCKET = "inputs"
  
  # Get your list of key values from your runspec
  rs = catr::translate_rs(.runspec = .runspec)
  # Get name of custom input database
  .custom = rs$defaultdbname
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
  
  # If provided, use and filter that
  if(f$is_custom){
    
    # Load data from file
    data = get_data(changes = f$changes, .geoidchar = .geoidchar)
    
    # Select final columns
    data = data %>% 
      select(sourceTypeID = sourcetypeid, 
             roadTypeID = roadtypeid,
             hourDayID = hourdayid,
             avgSpeedBinID = avgspeedbinid,
             avgSpeedFraction = avgspeedfraction)
    
    # Import the table
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = FALSE, save = TRUE, volume = BUCKET)
    
    # If not provided, estimate a default
  }else if(!f$is_custom){
    # Connect to database
    custom = connect("mariadb", .custom)
    
    # must not filter by roadtype here
    # Query
    data = custom %>% tbl(table) %>% 
      filter(hourDayID %in% !!.hourday) %>%
      collect()
    
    # Disconnect
    dbDisconnect(custom)
    
    # Import table!
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = TRUE, save = TRUE, volume = BUCKET)
    
    # Cleanup
    remove(data)
  }  
  
}
