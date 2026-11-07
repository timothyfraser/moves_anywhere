#!/bin/bash
# pushme.sh ###################################################################
#
# What:      Script to push the MOVES Anywhere image to the cloud.
# Does:      Tags moves_anywhere:v2 and pushes it to Docker Hub (tmf77/moves-anywhere:v2) and to
#            Google Cloud Artifact Registry, then prunes dangling images.
# Called by: Not used by v3. Legacy v2 image push (Docker Hub, Google Cloud).
#            For internal developer use only.
# Reads:     secret/.env (LOCATION, PROJECT_NAME, REPOSITORY), secret/key.json
# Writes:    the image in Docker Hub and in Artifact Registry
# Exits:     no explicit exit; the status of the last command
###############################################################################

# Set working directory
REPO="$(git rev-parse --show-toplevel)/moves_anywhere" && cd "$REPO"


# DOCKERHUB ###########################################
echo "-------Pushing to DockerHub--------"
IMAGE_NAME="tmf77/moves-anywhere:v2"
docker login
docker tag moves_anywhere:v2 "$IMAGE_NAME"
docker push "$IMAGE_NAME"
#docker pull tmf77/moves-anywhere:latest

# Remove the duplicate tagged image, in favor of its local name
docker image rm "$IMAGE_NAME"


# GOOGLE CLOUD #######################################

echo "-------Pushing to Google Cloud Artifact Registry--------"
# Load environmental variables PROJECT_NAME, REPOSITORY, 
source 'secret/.env'
IMAGE="moves-anywhere:v2"
IMAGE_NAME="$LOCATION-docker.pkg.dev/$PROJECT_NAME/$REPOSITORY/$IMAGE"
SOURCE_IMAGE="moves_anywhere:v2"

# Tag the image locally
docker tag $SOURCE_IMAGE $IMAGE_NAME
# Login with keyz
docker login -u _json_key --password-stdin "https://$LOCATION-docker.pkg.dev" < secret/key.json
# Push image to repository
docker push "$IMAGE_NAME"
# Logout
docker logout
# Remove the duplicate tagged image, in favor of its local name
docker image rm "$IMAGE_NAME"



# CLEANUP ################################################

echo "-------Pruning Unnecessary Files--------"
docker images -q -f "dangling=true"; 
docker rmi $(docker images -q -f "dangling=true");
docker image prune -f
