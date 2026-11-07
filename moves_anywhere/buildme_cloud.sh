#!/bin/bash
# buildme_cloud.sh ############################################################
#
# What:      Script to build the cloud version of moves_anywhere
# Does:      Runs dos2unix on scripts/*.sh, builds moves_anywhere:v3 with docker buildx
#            (builder cloud-catcornell-timbuild), then removes dangling images.
# Called by: Developer tool: builds the image. Not run by launch.sh.
# Reads:     Dockerfile and this folder (the build context), scripts/*.sh
# Writes:    local image moves_anywhere:v3; scripts/*.sh line endings, in place
# Exits:     no explicit exit; the status of the last command
###############################################################################


# STARTUP ################################################################
# Get moves_anywhere path
REPO="$(git rev-parse --show-toplevel)/moves_anywhere" && cd "$REPO"
# Path to image folder
IMAGE_FOLDER="$(pwd)"
# Set your DockerHub username
DOCKERHUB_USERNAME="tmf77"
# Set your Docker image name and tag
DOCKER_IMAGE_NAME="moves_anywhere"
DOCKER_IMAGE_TAG="v3"

# Get folder for MOVES Anywhere scripts
SCRIPTS="$(pwd)/scripts"
echo "$SCRIPTS"
# Process for use in linux
# dos2unix "$SCRIPTS/launch.sh"
# dos2unix "$SCRIPTS/launch_runspec.sh"
# dos2unix "$SCRIPTS/launch_fuse.sh"
# dos2unix "$SCRIPTS/task_check_inputs.sh"
# dos2unix "$SCRIPTS/task_start_mysql.sh"
# dos2unix "$SCRIPTS/task_launch_moves.sh"
# dos2unix "$SCRIPTS/task_copy_logs.sh"
# dos2unix "$SCRIPTS/task_copy_runspec.sh"
# dos2unix "$SCRIPTS/task_adapt.sh"
# dos2unix "$SCRIPTS/task_importer.sh"
# dos2unix "$SCRIPTS/task_fuse.sh"

# Process all files for use in linux
find "$SCRIPTS" -maxdepth 1 -name "*.sh" -print0 | while IFS= read -r -d '' file; do
  dos2unix "$file"
done

# Set working directory
cd "$IMAGE_FOLDER"
pwd

# Build
docker buildx build --builder cloud-catcornell-timbuild -t $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG .


# List dangling images
docker images -q -f "dangling=true"; 
docker rmi $(docker images -q -f "dangling=true");
docker image prune -f
