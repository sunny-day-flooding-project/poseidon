#! /bin/bash
#
# ##_make_rectify.sh
#		Rectify the original images and the labels and store in compressed arrays (zarr)
#
# NO TRAILING "/" ON FOLDERS!
# Some downstream code will fail.

echo "------------------------------------------------"
echo "Job Started: $(date)"
echo "------------------------------------------------"

# extract the script directory before any cd command is executed
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# This does conda initialization
if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
elif [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
    source "/opt/conda/etc/profile.d/conda.sh"
else
    echo "conda.sh not found"
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

# Point to your newly updated Python script
GRID_DIR="$REPO_ROOT/data/grids"
IMAGE_DIR="$REPO_ROOT/data/images-to-process"

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

	LIDAR_FILE="$REPO_ROOT/data/lidar/$SITE.laz"
	python -u "$REPO_ROOT/poseidon_deploy/naiads/run_rectify_single_event.py" \
		--lidar_file $LIDAR_FILE \
		--target_event_dir $IMAGE_DIR/$SITE \
		--min_x $MIN_X \
		--max_x $MAX_X \
		--min_y $MIN_Y \
		--max_y $MAX_Y \
		--camera_name $CAMERA_NAME \
		--intrinsics_name "suds_cam" \
		--grid_dir $GRID_DIR \
		--resolution $RESOLUTION \
		--lidar_units $LIDAR_UNITS \
		--grid_descr $GRID_DESCR \
		--image_subfolder 'orig_images' \
		--label_subfolder "labels" \
		--zarr_base "zarr" \
		--zarr_orig_name "orig_image_rects" \
		--zarr_label_name "labels_rects" \
		--disable_gpu
done

echo "Deactivating conda environment..."
conda deactivate

echo "Job finished."

echo "------------------------------------------------"
echo "Job Ended: $(date)"
echo "------------------------------------------------"

