# task_install_catr.R #########################################################
#
# What:      Script to install catr
# Does:      Installs catr 0.2.0 from source if that version is not installed, then prints the catr version.
# Called by: Dockerfile, at image build (RUN step), not a step of launch.sh.
#            Also run by the legacy launch_fuse.sh (v2, Google Cloud).
# Reads:     /cat/scripts/catr_0.2.0.tar.gz; the installed package list
# Writes:    catr into the R library
# Needs:     base R only
###############################################################################

# Runtime Variables
FOLDER="/cat/"

# Set working directory to /cat/
setwd(FOLDER)

# Get installed packages
packages = installed.packages()[, c("Package", "Version") ]
# Check if installed
name = "catr"
version = "0.2.0"
is_installed = any(packages[, "Package"] %in% name & packages[, "Version"] == version)

# If not installed...
if(!is_installed){
  # Install package from source
  install.packages("scripts/catr_0.2.0.tar.gz", type = "source")
}

# Print the package version of catr
cat(paste0("\n---catr version: ", packageVersion("catr"), "\n"))

# Close out
q(save = "no")