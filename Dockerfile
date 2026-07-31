# ------------------------------------------------------------
# Base image: Miniconda for development
# ------------------------------------------------------------
FROM continuumio/miniconda3:latest

# ------------------------------------------------------------
# Create a non-root user for OpenShift compatibility
# ------------------------------------------------------------
RUN useradd -m -u 1001 appuser

# ------------------------------------------------------------
# Install some necessary/useful programs
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y curl vim

# ------------------------------------------------------------
# Set HOME to /opt so scripts using $HOME/poseidon/... work
# ------------------------------------------------------------
ENV HOME=/opt

# ------------------------------------------------------------
# Create project directory
# ------------------------------------------------------------
RUN mkdir -p /opt/poseidon
WORKDIR /opt/poseidon


# ------------------------------------------------------------
# *** IMPORTANT: Install conda environments BEFORE copying project ***
# This allows Docker to cache the expensive conda solve layers.
# ------------------------------------------------------------
# Install Mamba into the base environment for fast, low-memory solves
RUN conda install -n base -c conda-forge mamba -y && conda clean -afy

# Gym environment
COPY poseidon_deploy/segmentation/segmentation_gym/install/gym.yml /tmp/gym.yml
RUN mamba env create -n gym -f /tmp/gym.yml && conda clean -afy

# Poseidon environment
COPY poseidon_deploy/poseidon-env.yml /tmp/poseidon-env.yml
RUN mamba env create -n poseidon -f /tmp/poseidon-env.yml && conda clean -afy



# make it so the c++ programs can find the libraries
ENV LD_LIBRARY_PATH=/opt/conda/envs/poseidon/lib:$LD_LIBRARY_PATH

# ------------------------------------------------------------
# Ensure conda.sh is available for activation in scripts
# ------------------------------------------------------------
ENV PATH="/opt/miniconda3/bin:${PATH}"

# ------------------------------------------------------------
# Copy entire poseidon directory into the container
# (This comes AFTER conda env creation for caching)
# ------------------------------------------------------------
COPY . /opt/poseidon/

# Fix permissions so appuser can write inside /opt/poseidon
RUN chown -R appuser:appuser /opt

# ------------------------------------------------------------
# Make sure all shell scripts are executable
# ------------------------------------------------------------
RUN find /opt/poseidon -type f -name "*.sh" -exec chmod +x {} \;

# ------------------------------------------------------------
# Switch to non-root user (required for OpenShift)
# ------------------------------------------------------------
USER appuser

# ------------------------------------------------------------
# Entrypoint: your master script
# ------------------------------------------------------------
ENTRYPOINT ["/opt/poseidon/poseidon_deploy/wsl_submission_scripts/process_all.sh"]
