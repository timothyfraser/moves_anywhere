# adapt_hotellingactivitydistribution.R #######################################
#
# What:      Adapts the hotellingactivitydistribution input table for the run.
# Does:      Uses inputs/hotellingactivitydistribution.csv if provided; otherwise copies the
#            default distribution (fake zoneID 990000) to each zone in the county.
# Called by: task_adapt.R, step 6 of launch.sh
# Reads:     EPA_MOVES_Model/rs_custom.xml (the runspec)
#            inputs/hotellingactivitydistribution.csv (optional)
#            tables zone, hotellingactivitydistribution in the default input database
# Writes:    inputs/_hotellingactivitydistribution.csv
# Needs:     adapt_functions.R (get_changes, get_is_custom, get_data, import_table)
#            catr, dplyr, stringr, DBI, RMariaDB
###############################################################################

#' Adapt the hotellingactivitydistribution table
#' @param .runspec path to the run's runspec (XML)
adapt_hotellingactivitydistribution = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  
  table = "hotellingactivitydistribution"
  BUCKET = "inputs"
  
  # Get your list of key values from your runspec
  rs = catr::translate_rs(.runspec = .runspec)
  # Get name of custom input database
  .custom = rs$defaultdbname
  .geoid = rs$geoid
  .geoidchar = stringr::str_pad(.geoid, width = 5, side = "left", pad = "0")
  
  # Get files for my bucket
  files = get_changes(BUCKET)
  
  # Classify that table as valid or not
  f = get_is_custom(files, table = table)   
  
  if(!table %in% files$changed){
    # Tentatively, if default, just skip. Use the defaults, no filtering.
    
    custom = connect("mariadb", .custom)
    # Download and filter the table
    ids = custom %>% tbl("zone") %>% filter(countyID %in% !!.geoid) %>% select(zoneID) %>% distinct() %>% collect()
    
    # Get base hotelling activity distribution,
    # set to fake zoneID 990000
    initial = custom %>% tbl("hotellingactivitydistribution") %>% 
      filter(zoneID %in% 990000) %>%
      collect() %>%
      # Remove the fake zoneID
      select(-zoneID)
    
    dbDisconnect(custom)
    
    # For each observed zoneID, we're going to duplicate the base hotelling activity distribution
    # which was set for fake zoneID 990000
    data = tibble(zoneID = ids$zoneID) %>%
      group_by(zoneID) %>%
      reframe(initial)
    
    # Import table!
    import_table(data = data, tablename = table, .custom = .custom, adapt = TRUE, save = TRUE, volume = BUCKET)
    # IF CUSTOMIZED
  }else if(table %in% files$changed){
    # Classify that table as valid or not
    f = get_is_custom(files, table = table)
    # Load data from file
    data = get_data(changes = f$changes, .geoidchar = .geoidchar)
    # get_names("hotellingactivitydistribution")
    data = data %>% 
      select(
        "zoneID" = "zoneid",
        "fuelTypeID" = "fueltypeid",
        "beginModelYearID" = "beginmodelyearid",
        "endModelYearID" = "endmodelyearid",
        "opModeID" = "opmodeid",
        "opModeFraction" = "opmodefraction"
      )
    # Import the table
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = FALSE, save = TRUE, volume = BUCKET)
  }
  
}