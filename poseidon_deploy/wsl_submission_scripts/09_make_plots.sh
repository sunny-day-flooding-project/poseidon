#! /bin/bash
#
# ##_make_plots.sh
#		Creates plots of the depth maps and water level time series. 
#
# NO TRAILING "/" ON FOLDERS!
# Some downstream code will fail.

echo "------------------------------------------------"
echo "Job Started: $(date)"
echo "------------------------------------------------"

# extract the script directory before any cd command is executed
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# This does conda initialization
source "$HOME/miniconda3/etc/profile.d/conda.sh"

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

export TMPDIR=/tmp
export PROJ_NETWORK=OFF
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
	BASEMAP_FILE="$REPO_ROOT/data/basemaps/${SITE}_basemap.tif"
	if [ ! -d "${TARGET_EVENT_DIR}/zarr" ]; then
		echo "ERROR: Zarr directory not found: ${TARGET_EVENT_DIR}/zarr.  Continuing."
		continue
	fi

	echo "Starting plotter Python script..."
	python -u "$REPO_ROOT/poseidon_deploy/naiads/run_plotter_single_event_no_csv.py" \
		--target_event_dir $TARGET_EVENT_DIR \
		--location $CAMERA_NAME \
		--basemap $BASEMAP_FILE \
		--min_x $MIN_X \
		--max_x $MAX_X \
		--min_y $MIN_Y \
		--max_y $MAX_Y \
		--bbox_crs $BBOX_CRS \
		--resolution $RESOLUTION \
		--stats "95_perc"
done

set +x
echo "Deactivating conda environment..."
conda deactivate
echo "Job finished."
