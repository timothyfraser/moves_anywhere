# adapt_roadtypedistribution.R ################################################
#
# What:      adapt road type distribution
# Does:      Uses a custom inputs/roadtypedistribution.csv if provided; otherwise takes the
#            default roadtypedistribution table, unfiltered.
# Called by: task_adapt.R, step 6 of launch.sh
# Reads:     EPA_MOVES_Model/rs_custom.xml (runspec); inputs/roadtypedistribution.csv if provided,
#            otherwise the roadtypedistribution table in the runspec's default database (MariaDB)
# Writes:    inputs/_roadtypedistribution.csv
# Needs:     adapt_functions.R (get_changes, get_is_custom, get_data, import_table); catr, DBI, RMariaDB, dplyr, stringr, tidyr
###############################################################################

#' Adapt the roadtypedistribution table
#' @param .runspec path to the run's runspec (XML)
adapt_roadtypedistribution = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  
  table = "roadtypedistribution"
  BUCKET = "inputs"
  
  # Get your list of key values from your runspec
  rs = catr::translate_rs(.runspec = .runspec)
  # Get name of custom input database
  .custom = rs$defaultdbname
  .geoid = rs$geoid
  .geoidchar = stringr::str_pad(.geoid, width = 5, side = "left", pad = "0")
  .hour = rs$hour # eg. 1:24,
  .day = rs$day  # eg. c(2,5)
  .hourday = tidyr::expand_grid(hour = .hour, day = .day) %>%
    mutate(hourday = paste0(hour, day)) %>% with(hourday)
  
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
             roadTypeVMTFraction = roadtypevmtfraction)
    
    
    # print(data)
    
    # Import the table
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = FALSE, save = TRUE, volume = BUCKET)
    
    # If not provided, estimate a default
  }else if(!f$is_custom){
    # Connect to database
    custom = connect("mariadb", .custom)
    
    # must not filter by roadtype here
    # Query
    data = custom %>% tbl(table) %>% 
      # filter(hourDayID %in% !!.hourday) %>%
      collect()
    
    
    # Disconnect
    dbDisconnect(custom)
    
    # Import table!
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = TRUE, save = TRUE, volume = BUCKET)
    
    # Cleanup
    remove(data)
  }  
  
}
