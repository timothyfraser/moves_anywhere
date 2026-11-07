# adapt_startsopmodedistribution.R ############################################
#
# What:      Adapter for the startsopmodedistribution input table.
# Does:      If the user supplied a startsopmodedistribution CSV, selects its columns, marks it
#            isUserInput = "Y" and imports it; if not, skips it and MOVES uses the defaults.
# Called by: task_adapt.R, step 6 of launch.sh
# Reads:     the runspec; the startsopmodedistribution CSV in inputs/, if supplied
# Writes:    inputs/_startsopmodedistribution.csv (via import_table), only when supplied
# Needs:     adapt_functions.R (get_changes, get_is_custom, get_data, import_table),
#            sourced by task_adapt.R; catr (translate_rs); dplyr, stringr
###############################################################################

#' Adapt the startsopmodedistribution table
#' @param .runspec path to the run's runspec (XML)
adapt_startsopmodedistribution = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  
  ### startsopmodedistribution #################################  
  table = "startsopmodedistribution"
  
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
    # Connect
    # custom = connect("mariadb", .custom)
    # Query
    # data = custom %>% tbl("startsopmodedistribution") %>% filter(opModeID %in% !!ids$opModeID, dayID %in% !!.day, hourID %in% !!.hour) %>% collect()
    # dbDisconnect(custom)
    # Import table!
    # import_table(data = data, tablename = table, .custom = .custom, adapt = TRUE, save = TRUE, volume = BUCKET)
    # IF CUSTOMIZED
  }else if(table %in% files$changed){
    # Classify that table as valid or not
    f = get_is_custom(files, table = table)
    # Load data from file
    data = get_data(changes = f$changes, .geoidchar = .geoidchar)
    # get_names(table = "startsopmodedistribution")
    data = data %>% 
      select(
        "dayID" = "dayid",
        "hourID" = "hourid",
        "sourceTypeID" = "sourcetypeid",
        "ageID" = "ageid",
        "opModeID" = "opmodeid",
        "opModeFraction" = "opmodefraction",
        "isUserInput" = "isuserinput"
      ) %>%
      mutate(isUserInput = "Y") # clarify that it is user-input
    # Import the table
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = FALSE, save = TRUE, volume = BUCKET)
  }
  
}