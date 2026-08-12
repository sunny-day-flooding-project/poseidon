#!/usr/bin/env bash
set -eo pipefail


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


# Use $HOME/poseidon by default, but allow overrides from the environment.
REPO_ROOT=$HOME/poseidon
ENV_FILE="$REPO_ROOT/poseidon_deploy/hpc_paths.env"
PYTHON="${PYTHON:-}"

# Load shared environment variables if present.
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    echo "Loaded environment variables from $ENV_FILE"
fi

# Activate the configured conda environment if available.
if [ -n "${POSEIDON_ENV:-}" ]; then
    echo "Activating conda environment $POSEIDON_ENV"
    conda activate "$POSEIDON_ENV"
    PYTHON="${PYTHON:-$(command -v python)}"
else
    PYTHON="${PYTHON:-$(command -v python)}"
fi

# Use the app package directory as the PYTHONPATH root.
APP_ROOT="$REPO_ROOT/poseidon_deploy/sdfp_file_handler"

# Add both APP_ROOT and REPO_ROOT to PYTHONPATH
export PYTHONPATH="$REPO_ROOT:$APP_ROOT:${PYTHONPATH:-}"

cd "$APP_ROOT"

echo "Running copyfiles"
"$PYTHON" -m app.main copyfiles

echo "Running job list creation and downstream processing"
"$REPO_ROOT/poseidon_deploy/wsl_submission_scripts/99_create_job_lists.sh"
"$REPO_ROOT/poseidon_deploy/wsl_submission_scripts/02_segment_lists.sh"
"$REPO_ROOT/poseidon_deploy/wsl_submission_scripts/03_make_labels.sh"
"$REPO_ROOT/poseidon_deploy/wsl_submission_scripts/04_make_overlays.sh"

echo "Running storeresults"
"$PYTHON" -m app.main storeresults

if [ -n "${POSEIDON_ENV:-}" ]; then
    echo "Deactivating conda environment"
    conda deactivate
fi
