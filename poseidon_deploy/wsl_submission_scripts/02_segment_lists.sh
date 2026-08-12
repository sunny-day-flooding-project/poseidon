#! /bin/bash
# ##_segment_lists.sh
#		Runs segmentation model on files in file list and stores output.
#
# NO TRAILING "/" ON FOLDERS!
# Some downstream code will fail.

echo "------------------------------------------------"
echo "Job Started: $(date)"
echo "------------------------------------------------"

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
#conda activate gym
conda activate poseidon

export TRANSFORMERS_OFFLINE=1
export TRANSFORMERS_CACHE="$REPO_ROOT/poseidon_deploy/segmentation/segmentation_gym/hf_cache_portable"

# Add only if the directory exists (WSL)
if [ -d "/usr/lib/wsl/lib" ]; then
	# WSL specific export to add to load library path
    export LD_LIBRARY_PATH="/usr/lib/wsl/lib:$LD_LIBRARY_PATH"
fi

# --- CONFIGURATION ---
CONTAINER_PATH="${REPO_ROOT}/poseidon_deploy/segmentation/container/seg_gym.sif"
WEIGHTS_FILE="${REPO_ROOT}/poseidon_deploy/segmentation/models/all_sites_5_class_v3_segformer_fullmodel.h5"
IMAGE_DIR="$REPO_ROOT/data/images-to-process"

# (This matches ??_*, but excludes if there is another _ or - in case of long-named folders like *_backup etc)
for SITE_PATH in $IMAGE_DIR/??_[!_-]*; do
	SITE="${SITE_PATH##*/}"
    echo "Processing site: $SITE"

	FILE_LIST="${IMAGE_DIR}/$SITE/job_file_lists/file_list_1.txt"

	if [ ! -f "${FILE_LIST}" ]; then
		echo "ERROR: File list not found: ${FILE_LIST}"
		exit 1
	fi

	python ${REPO_ROOT}/poseidon_deploy/segmentation/segmentation_gym/seg_images_in_folder_no_tkinter.py \
	--images_dir ${IMAGE_DIR}/$SITE/orig_images \
	--weights ${WEIGHTS_FILE} \
	--file_list ${FILE_LIST}

	# move the output
	mv ${IMAGE_DIR}/$SITE/orig_images/meta ${IMAGE_DIR}/$SITE/preds
done


echo "------------------------------------------------"
echo "Job Ended: $(date)"
echo "------------------------------------------------"
