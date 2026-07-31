#! /bin/bash

#
# Filter the image files to exclude ones that will not
# yield results (e.g. night at some sites)
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
# This script will probably need updating
# It might make more sense to simply delete images that we
# don't want to process from the IMAGE_DIR and not make another
# copy in the OUTPUT_DIR.
#
RUNNER_SCRIPT="$REPO_ROOT/poseidon_deploy/naiads/run_image_filter.py"

IMAGE_DIR="$REPO_ROOT/data/images-to-process"
OUTPUT_DIR="$REPO_ROOT/data/carolina_beach/images/daylight_all_events"

echo "Starting photo filter Python script..."
python -u $RUNNER_SCRIPT \
    --drive $IMAGE_DRIVE \
    --image_dir $IMAGE_DIR \
    --dest $OUTPUT_DIR \
    --lat 34.0435 \
    --lon -77.8894

echo "Deactivating conda environment..."
conda deactivate

echo "Job finished."
