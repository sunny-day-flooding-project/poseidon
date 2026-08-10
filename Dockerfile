# ============================================================
# STAGE 1: Builder
# In order to reduce memory load on OpenShift, heavy dependency
# resolution & installation happens here in its own build stage
# ============================================================
FROM continuumio/miniconda3:latest AS builder

# Copy environment definitions
COPY poseidon_deploy/segmentation/segmentation_gym/install/gym.yml /tmp/gym.yml
COPY poseidon_deploy/poseidon-env.yml /tmp/poseidon-env.yml

# Build both conda environments with leaner solver and clean up temporary caches
RUN conda install -n base conda-libmamba-solver -y && \
    conda config --set solver libmamba && \
    conda env create -n gym -f /tmp/gym.yml && \
    conda env create -n poseidon -f /tmp/poseidon-env.yml && \
    conda clean -afy

# ============================================================
# STAGE 2: Final Runtime Image
# Lean stage deployed on OpenShift
# ============================================================
FROM continuumio/miniconda3:latest

# Create non-root user for OpenShift compatibility
RUN useradd -m -u 1001 appuser

# Install system dependencies
RUN apt-get update && apt-get install -y curl vim && rm -rf /var/lib/apt/lists/*

# Set HOME directory
ENV HOME=/opt

# Create project directory
RUN mkdir -p /opt/poseidon
WORKDIR /opt/poseidon

# Copy the pre-built conda environments from the builder stage
COPY --from=builder /opt/conda/envs /opt/conda/envs

# Set up environment variables
ENV LD_LIBRARY_PATH=/opt/conda/envs/poseidon/lib:$LD_LIBRARY_PATH
ENV PATH="/opt/conda/bin:/opt/conda/envs/poseidon/bin:${PATH}"

# Copy application source code into the container
COPY . /opt/poseidon/

# Fix permissions for appuser
RUN chown -R appuser:appuser /opt && \
    find /opt/poseidon -type f -name "*.sh" -exec chmod +x {} \;

# Switch to non-root user
USER appuser

# Entrypoint
ENTRYPOINT ["/opt/poseidon/poseidon_deploy/wsl_submission_scripts/process_all.sh"]