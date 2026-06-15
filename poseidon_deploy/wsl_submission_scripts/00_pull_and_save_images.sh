#! /bin/bash

#
# The logic for this will change for a real-time production environment.  Each time this script runs
# we will gather together (the names of?) all unprocessed images with some sort of reasonable limit 
# based on expected processing time.
#

# This does conda initialization
source $HOME/.bashrc

REPO_ROOT=$HOME/poseidon
ENV_FILE="$REPO_ROOT/poseidon_deploy/hpc_paths.env"

# Load the env file if it exists
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    echo "Loaded environment variables from $ENV_FILE"
else
    echo "Warning: No hpc_paths.env file found at $ENV_FILE"
fi

echo "Activating conda environment..."
conda activate $POSEIDON_ENV

#
# The RUNNER_SCRIPT will have to change to do all images
# We will not need the event spreadsheet
#
RUNNER_SCRIPT="$REPO_ROOT/poseidon_deploy/naiads/run_image_pull.py"
EVENT_CSV="$REPO_ROOT/data/carolina_beach/abbr_flood_events.csv"

OUTPUT_DIR="$REPO_ROOT/data/images-to-process"

echo "Starting photo pull Python script..."
python -u $RUNNER_SCRIPT \
    --drive $IMAGE_DRIVE \
    --dest $OUTPUT_DIR \
    --csv $EVENT_CSV \
    --buffer 3

echo "Deactivating conda environment..."
conda deactivate

echo "Job finished."
