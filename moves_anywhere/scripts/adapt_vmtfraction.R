# adapt_vmtfraction.R #########################################################
#
# What:      Adapters for the dayvmtfraction, hourvmtfraction and monthvmtfraction input tables.
# Does:      Three functions, one per table: each imports the user's CSV if supplied, otherwise
#            filters the default table to the runspec's months, days (and hours) and imports that.
# Called by: task_adapt.R, step 6 of launch.sh
# Reads:     the runspec; the dayvmtfraction, hourvmtfraction and monthvmtfraction CSVs in
#            inputs/, if supplied; otherwise the same tables in the custom input database
# Writes:    inputs/_dayvmtfraction.csv, inputs/_hourvmtfraction.csv,
#            inputs/_monthvmtfraction.csv (via import_table)
# Needs:     adapt_functions.R (get_changes, get_is_custom, get_data, import_table),
#            sourced by task_adapt.R; catr (translate_rs); dplyr, stringr, tidyr, DBI;
#            catr (connect)
###############################################################################

#' Adapt the dayvmtfraction table
#' @param .runspec path to the run's runspec (XML)
adapt_dayvmtfraction = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  
    table = "dayvmtfraction"
    BUCKET = "inputs"
    
    # Get your list of key values from your runspec
    rs = catr::translate_rs(.runspec = .runspec)
    # Get name of custom input database
    .month = rs$month # eg. 1:12,
    .hour = rs$hour # eg. 1:24,
    .day = rs$day  # eg. c(2,5)
    .hourday = tidyr::expand_grid(hour = .hour, day = .day) %>%
      mutate(hourday = paste0(hour, day)) %>% with(hourday)
    .custom = rs$defaultdbname
    .geoid = rs$geoid
    .geoidchar = stringr::str_pad(.geoid, width = 5, side = "left", pad = "0")

    # Get files for my bucket
    files = get_changes(BUCKET)
    
    
  f = get_is_custom(files, table = table)   

  # If provided, use and filter that
  if(f$is_custom){

    # Load data from file
    data = get_data(changes = f$changes, .geoidchar = .geoidchar)

    # Select final columns
    data = data %>% 
      select(sourceTypeID = sourcetypeid, monthID = monthid,
      roadTypeID = roadtypeid, dayID = dayid, dayVMTFraction = dayvmtfraction)

    # Import the table
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = FALSE, save = TRUE, volume = BUCKET)
    
  # If not provided, estimate a default
  }else if(!f$is_custom){
  
    # Connect to database
    custom = connect("mariadb", .custom)
    
    # must not filter by roadtype here
    # Query
    data = custom %>% tbl("dayvmtfraction") %>% 
      filter(monthID %in% !!.month,
             dayID %in% !!.day) %>% 
      collect()
    # Disconnect
    dbDisconnect(custom)
    
    # Import table!
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = TRUE, save = TRUE, volume = BUCKET)

    # Cleanup
    remove(data)
  }  
    
}



adapt_hourvmtfraction = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  
    table = "hourvmtfraction"
    BUCKET = "inputs"
    
    # Get your list of key values from your runspec
    rs = catr::translate_rs(.runspec = .runspec)
    # Get name of custom input database
    .month = rs$month # eg. 1:12,
    .hour = rs$hour # eg. 1:24,
    .day = rs$day  # eg. c(2,5)
    .hourday = tidyr::expand_grid(hour = .hour, day = .day) %>%
      mutate(hourday = paste0(hour, day)) %>% with(hourday)
    .custom = rs$defaultdbname
    .geoid = rs$geoid
    .geoidchar = stringr::str_pad(.geoid, width = 5, side = "left", pad = "0")

    # Get files for my bucket
    files = get_changes(BUCKET)
    
    
  f = get_is_custom(files, table = table)   

  # If provided, use and filter that
  if(f$is_custom){

    # Load data from file
    data = get_data(changes = f$changes, .geoidchar = .geoidchar)

    
    # Select final columns
    data = data %>% 
      select(sourceTypeID = sourcetypeid, roadTypeID = roadtypeid, 
        dayID = dayid, hourID = hourid, hourVMTFraction = hourvmtfraction)

    # Import the table
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = FALSE, save = TRUE, volume = BUCKET)
    
  # If not provided, estimate a default
  }else if(!f$is_custom){
  
    # Connect to database
    custom = connect("mariadb", .custom)
    
    # must not filter by roadtype here
    # Query
    data = custom %>% tbl("hourvmtfraction") %>% 
      filter(dayID %in% !!.day, hourID %in% !!.hour) %>% 
      collect()
    # Disconnect
    dbDisconnect(custom)
    
    # Import table!
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = TRUE, save = TRUE, volume = BUCKET)

    # Cleanup
    remove(data)
  }  
    
}



adapt_monthvmtfraction = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  
    table = "monthvmtfraction"
    BUCKET = "inputs"
    
    # Get your list of key values from your runspec
    rs = catr::translate_rs(.runspec = .runspec)
    # Get name of custom input database
    .month = rs$month # eg. 1:12,
    .hour = rs$hour # eg. 1:24,
    .day = rs$day  # eg. c(2,5)
    .hourday = tidyr::expand_grid(hour = .hour, day = .day) %>%
      mutate(hourday = paste0(hour, day)) %>% with(hourday)
    .custom = rs$defaultdbname
    .geoid = rs$geoid
    .geoidchar = stringr::str_pad(.geoid, width = 5, side = "left", pad = "0")

    # Get files for my bucket
    files = get_changes(BUCKET)
    
    
  f = get_is_custom(files, table = table)   

  # If provided, use and filter that
  if(f$is_custom){
    # Load data from file
    data = get_data(changes = f$changes, .geoidchar = .geoidchar)

    
    # Select final columns
    data = data %>% 
      select(sourceTypeID = sourcetypeid, monthID = monthid, monthVMTFraction = monthvmtfraction)

    # Import the table
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = FALSE, save = TRUE, volume = BUCKET)
    
  # If not provided, estimate a default
  }else if(!f$is_custom){
  
    # Connect to database
    custom = connect("mariadb", .custom)
    
    # must not filter by roadtype here
    # Query
    data = custom %>% tbl("monthvmtfraction") %>% 
      filter(monthID %in% !!.month) %>% 
      collect()
    # Disconnect
    dbDisconnect(custom)
    
    # Import table!
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = TRUE, save = TRUE, volume = BUCKET)

    # Cleanup
    remove(data)
  }  
    
}
  
