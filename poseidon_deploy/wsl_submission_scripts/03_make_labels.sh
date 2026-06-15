#!/bin/bash
# ##_make_labels.sh
#		Makes label files and stores output.
#
# NO TRAILING "/" ON FOLDERS!
# Some downstream code will fail.

echo "------------------------------------------------"
echo "Job Started: $(date)"
echo "------------------------------------------------"

# Exit immediately if a command exits with a non-zero status.
set -e

REPO_ROOT=$HOME/poseidon
IMAGE_DIR="$REPO_ROOT/data/images-to-process"

# (This matches ??_*, but excludes if there is another _ or - in case of long-named folders like *_backup etc)
for SITE_PATH in $IMAGE_DIR/??_[!_-]*; do
	SITE="${SITE_PATH##*/}"
    echo "Processing site: $SITE"

	# Directories
	PREDS_DIR="$IMAGE_DIR/$SITE/preds"
	LISTS_DIR="$IMAGE_DIR/$SITE/job_file_lists"
	OUTPUT_DIR="$IMAGE_DIR/$SITE/labels"

	# read the top-level file-list and modify
	FILE_LIST="${LISTS_DIR}/file_list_1.txt"
	mkdir -p $PREDS_DIR/job_file_lists
	sed 's/\.jpg$/_predseg.png/' $FILE_LIST > $PREDS_DIR/job_file_lists/file_list_1.txt
	FILE_LIST="$PREDS_DIR/job_file_lists/file_list_1.txt"

	echo "This task will process the file list: ${FILE_LIST}"

	# Sanity check that file list exists
	if [ ! -f "${FILE_LIST}" ]; then
		echo "FATAL ERROR: File list not found: ${FILE_LIST}"
		exit 1
	fi

	echo "Executing overlay generator..."

	"$REPO_ROOT/poseidon_utils/bin/pred_label_generator" \
		"${PREDS_DIR}" \
		"${FILE_LIST}" \
		"${OUTPUT_DIR}" 
done

echo "------------------------------------------------"
echo "Job Ended: $(date)"
echo "------------------------------------------------"
