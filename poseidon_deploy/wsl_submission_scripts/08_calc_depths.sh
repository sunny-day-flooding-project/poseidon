#! /bin/bash
#
# ##_calc_depths.sh
#		Calculates depth maps using DEM and rectified labels. Also autogenerates 
#		histograms of the ponding edge elevations.
#
# NO TRAILING "/" ON FOLDERS!
# Some downstream code will fail.

echo "------------------------------------------------"
echo "Job Started: $(date)"
echo "------------------------------------------------"

# extract the script directory before any cd command is executed
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

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

export MPI4PY_RC_INITIALIZE=False

GRID_DIR="$REPO_ROOT/data/grids"
IMAGE_DIR="$REPO_ROOT/data/images-to-process"

set -x
# (This matches ??_*, but excludes if there is another _ or - in case of long-named folders like *_backup etc)
for SITE_PATH in $IMAGE_DIR/??_[!_-]*; do
	SITE="${SITE_PATH##*/}"
    echo "Processing site: $SITE"

	cd $SCRIPT_DIR
    if [[ ! -f "$SITE.conf" ]]; then
        echo "Warning: config file '$SITE.conf' not found, skipping site '$SITE'" >&2
        continue
    fi
	# read in the variables from the config file
	source "$SITE.conf"

	TARGET_EVENT_DIR="$IMAGE_DIR/$SITE"
	if [ ! -d "${TARGET_EVENT_DIR}/zarr" ]; then
		echo "ERROR: Zarr directory not found: ${TARGET_EVENT_DIR}/zarr.  Continuing."
		continue
	fi

	echo "Starting Depth Calculation Python script..."
	python -u "$REPO_ROOT/poseidon_deploy/naiads/run_calc_depths_single_event.py" \
		--target_event_dir $TARGET_EVENT_DIR \
		--grid_dir $GRID_DIR \
		--grid_descr $GRID_DESCR \
		--zarr_base "zarr" \
		--zarr_label_dir "labels_rects" \
		--zarr_depth_dir "depth_maps" \
		--plot_base_dir "plots"
done

set +x
echo "Deactivating conda environment..."
conda deactivate

echo "------------------------------------------------"
echo "Job Ended: $(date)"
echo "------------------------------------------------"

