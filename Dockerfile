# ==========================================
# STAGE 1: Builder (micromamba)
# ==========================================
FROM mambaorg/micromamba:ubuntu24.04 AS builder

USER root
RUN mkdir -p /opt/poseidon /opt/.conda /opt/.cache /opt/.config && \
    chown -R $MAMBA_USER:$MAMBA_USER /opt/poseidon /opt/.conda /opt/.cache /opt/.config

USER $MAMBA_USER
ENV HOME=/opt
ENV CONDA_PKGS_DIRS=/opt/.cache/conda/pkgs

COPY --chown=$MAMBA_USER:$MAMBA_USER poseidon_deploy/combined-environment.yml /tmp/combined-environment.yml

RUN micromamba env create -y -n poseidon -f /tmp/combined-environment.yml && \
    micromamba clean --all --yes


# ==========================================
# STAGE 2: Runtime (micromamba)
# ==========================================
FROM mambaorg/micromamba:ubuntu24.04

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    vim-tiny \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/vim.tiny /usr/local/bin/vim

# Use existing micromamba user (uid=1000, gid=1000)
# Make it OpenShift-friendly by adding it to group 0
RUN usermod -g 0 mambauser && \
    mkdir -p /opt/poseidon /tmp/matplotlib /tmp/cache && \
    chown -R mambauser:0 /opt /tmp/matplotlib /tmp/cache && \
    chmod -R 775 /opt /tmp/matplotlib /tmp/cache

# Copy full micromamba environment + metadata
COPY --from=builder --chown=mambauser:0 /opt/conda/envs/poseidon /opt/conda/envs/poseidon
COPY --from=builder --chown=mambauser:0 /opt/.conda /opt/.conda
COPY --from=builder --chown=mambauser:0 /opt/.cache /opt/.cache
COPY --from=builder --chown=mambauser:0 /opt/.config /opt/.config

# Convenience symlink
RUN ln -s /usr/bin/micromamba /usr/local/bin/conda || true

# Copy application code
COPY --chown=mambauser:0 . /opt/poseidon/

# Make shell scripts executable
RUN find /opt/poseidon -type f -name "*.sh" -exec chmod +x {} \;

# Runtime environment
ENV HOME=/opt
ENV PATH=/opt/conda/envs/poseidon/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/conda/envs/poseidon/lib
ENV MPLCONFIGDIR=/tmp/matplotlib
ENV XDG_CACHE_HOME=/tmp/cache

USER mambauser
WORKDIR /opt/poseidon

ENTRYPOINT ["/opt/poseidon/poseidon_deploy/wsl_submission_scripts/process_all.sh"]




# # ------------------------------------------------------------
# # Base image: Lightweight Micromamba (C++ Conda engine)
# # ------------------------------------------------------------
# FROM mambaorg/micromamba:ubuntu24.04
# 
# # ------------------------------------------------------------
# # Set environment variables
# # ------------------------------------------------------------
# ENV HOME=/opt
# ENV PATH=/opt/conda/envs/poseidon/bin:$PATH
# 
# # Switch to root briefly to install system packages and set permissions
# USER root
# 
# # Install required system packages and clean up apt cache in the same step
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     curl \
#     vim \
#     && rm -rf /var/lib/apt/lists/*
# 
# # Create a symlink so calls to 'conda' use 'micromamba' directly
# RUN ln -s /usr/bin/micromamba /usr/local/bin/conda
# 
# # Create target directory and pre-create hidden config/cache directories
# RUN mkdir -p /opt/poseidon /opt/.conda /opt/.cache /opt/.config && \
#     chown -R $MAMBA_USER:$MAMBA_USER /opt/poseidon /opt/.conda /opt/.cache /opt/.config
# 
# WORKDIR /opt/poseidon
# 
# # ------------------------------------------------------------
# # Install combined Conda environment
# # ------------------------------------------------------------
# # Copy unified environment spec using $MAMBA_USER
# COPY --chown=$MAMBA_USER:$MAMBA_USER poseidon_deploy/combined-environment.yml /tmp/combined-environment.yml
# 
# # Switch back to non-root user for environment build
# USER $MAMBA_USER
# 
# # Point package cache to the pre-created /opt/.cache directory
# ENV CONDA_PKGS_DIRS=/opt/.cache/conda/pkgs
# 
# # Create single 'poseidon' environment and strip cache immediately
# RUN micromamba env create -y -n poseidon -f /tmp/combined-environment.yml && \
#     micromamba clean --all --yes
# 
# # Point C++ shared libraries to the active environment
# ENV LD_LIBRARY_PATH=/opt/conda/envs/poseidon/lib
# 
# # ------------------------------------------------------------
# # Copy application code
# # ------------------------------------------------------------
# COPY --chown=$MAMBA_USER:$MAMBA_USER . /opt/poseidon/
# 
# # Make all shell scripts executable
# RUN find /opt/poseidon -type f -name "*.sh" -exec chmod +x {} \;
# 
# # ------------------------------------------------------------
# # Entrypoint execution
# # ------------------------------------------------------------
# ENTRYPOINT ["/opt/poseidon/poseidon_deploy/wsl_submission_scripts/process_all.sh"]
