# adapt_sourcetypeyear2.R #####################################################
#
# What:      Script to adapt sourcetypeyear table, by adapting NEI MOVES inputs
# Does:      Uses a custom inputs/sourcetypeyear.csv if provided; otherwise builds sourcetypeyear
#            from NEI inputs with adapt_vehicles_from_nei().
# Called by: task_adapt.R, step 6 of launch.sh
# Reads:     EPA_MOVES_Model/rs_custom.xml (runspec); inputs/sourcetypeyear.csv if provided;
#            otherwise scripts/reference/sourcetypeyear.csv, scripts/reference/nei_sourcetypeyear.rds,
#            scripts/projections.rds
# Writes:    inputs/_sourcetypeyear.csv
# Needs:     adapt_functions.R (get_changes, get_data, import_table); adapt_from_nei.R
#            (adapt_vehicles_from_nei); catr, dplyr, readr, stringr
###############################################################################

#' Adapt the sourcetypeyear table from NEI inputs
#' @param .runspec path to the run's runspec (XML)
adapt_sourcetypeyear2 = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  
  library(dplyr, warn.conflicts = FALSE, quietly = TRUE)
  library(readr, warn.conflicts = FALSE, quietly = TRUE)
  
  table = "sourcetypeyear"
  BUCKET = "inputs"
  
  # Get your list of key values from your runspec
  rs = catr::translate_rs(.runspec = .runspec)
  # Get name of custom input database
  .custom = rs$defaultdbname
  .geoid = rs$geoid
  .year = rs$year
  .geoidchar = stringr::str_pad(.geoid, width = 5, side = "left", pad = "0")
  
  # Get files for my bucket
  files = get_changes(BUCKET)
  
  # Check if that custom input table is provided among the provided input tables
  f = files %>% filter(changed == table)
  # Get number of matching tables
  f_n = nrow(f)
  # Error handling
  if(f_n > 1){ stop("Multiple MOVES input files of the same name provided. Stopping...")}
  
  # Is the table of interest provided as a custom input file?
  is_custom = f_n == 1
  
  # If provided, use and filter that
  if(is_custom){
    # Load in data    
    data = get_data(changes = f$changes, .geoidchar = .geoidchar)
    
    # Filter by year
    data = data %>% filter(yearid == .year)    
    
    # Select final columns
    data = data %>% 
      select(yearID = yearid, sourceTypeID = sourcetypeid, sourceTypePopulation = sourcetypepopulation)
    # Test out
    # data = data %>%
    #   mutate(sourceTypePopulation = sourceTypePopulation * 100)
    
    # Import the table
    import_table(data = data, tablename = table, .custom = .custom, adapt = FALSE, save = TRUE, volume = BUCKET)
    
    
    # If not provided, estimate a default
  }else if(!is_custom){
    
    data = adapt_vehicles_from_nei(
      .geoidchar = .geoidchar,
      .year = .year,
      path_sourcetypeyear = "scripts/reference/sourcetypeyear.csv",
      path_nei_sourcetypeyear = "scripts/reference/nei_sourcetypeyear.rds",
      path_projections = "scripts/projections.rds"
    )
    # Import table!
    import_table(data = data, tablename = table, .custom = .custom, adapt = TRUE, save = TRUE, volume = BUCKET)
    
  }
  
  
}
