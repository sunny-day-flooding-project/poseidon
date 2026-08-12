#! /bin/bash
# ##_create_job_lists.sh
#		Simply creates a list of files to be processed and stores it for later.
#
# NO TRAILING "/" ON FOLDERS!
# Some downstream code will fail.
#

echo "------------------------------------------------"
echo "Job Started: $(date)"
echo "------------------------------------------------"

# This does conda initialization
# Check if running in Docker/Container where environment is pre-activated in PATH
if [ -n "$IS_DOCKER" ] || [[ "$PATH" == *"/opt/conda/envs/poseidon/bin"* ]]; then
    echo "Container environment detected; skipping Conda/Micromamba activation."
    conda() { return 0; }
elif [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
    source "/opt/conda/etc/profile.d/conda.sh"
elif [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
elif command -v micromamba >/dev/null 2>&1; then
    eval "$(micromamba shell hook --shell bash)"
    conda() { micromamba "$@"; }
else
    echo "Neither conda.sh nor micromamba was found"
    exit 1
fi



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

IMAGE_DIR="$REPO_ROOT/data/images-to-process"

echo "Starting job list creation Python script..."
# (This matches ??_*, but excludes if there is another _ or - in case of long-named folders like *_backup etc)
for SITE_PATH in $IMAGE_DIR/??_[!_-]*; do
	SITE="${SITE_PATH##*/}"
    echo "Processing site: $SITE"
	OUTPUT_DIR="$IMAGE_DIR/$SITE/job_file_lists"

	python -u "$REPO_ROOT/poseidon_deploy/naiads/run_create_file_lists.py" \
		--image_dir $IMAGE_DIR/$SITE/orig_images \
		--output_dir $OUTPUT_DIR \
		--num_jobs 1 
done

echo "Deactivating conda environment..."
conda deactivate

echo "Job finished."

echo "------------------------------------------------"
echo "Job Ended: $(date)"
echo "------------------------------------------------"
