# task_check_packages.R #######################################################
#
# What:      Script to check if all necessary packages are installed.
# Does:      Compares a list of needed packages with installed.packages() and prints how many
#            are missing, or "R packages ready." It does not stop the run. The list still
#            includes three Google packages: googleCloudStorageR, googleAuthR, gargle.
# Called by: launch.sh, step 4 of launch.sh
# Reads:     the installed R packages
# Writes:    nothing (prints to the log)
# Needs:     base R only
###############################################################################

# Get installed packages
p = as.data.frame(installed.packages())

# Which of these packages do we have?
needed = c("lubridate", "dplyr", "readr", 
           "purrr",  "tidyr", "stringr", 
           "DBI", "dbplyr", "RMariaDB", "RMySQL",
           "googleCloudStorageR",
           "remotes",
           "googleAuthR",
           "gargle",
           "httr",
           "jsonlite",
           "xml2",
           "catr"
)

# Are there any packages that are needed but are not installed?
remaining = needed[!needed %in% p$Package]

n_remaining = length(remaining)

if(n_remaining > 0){
  cat("---", n_remaining, " R packages need installed: ", paste0(remaining, collaspse = ", "), "\n")
}else{
  cat("---R packages ready.\n")
}

# Close R
q(save = "no")

