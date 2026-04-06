FROM mcr.microsoft.com/devcontainers/python:3.12-bookworm

# jq is required by kokko-cmds plugin hooks (JSON parsing of hook input)
RUN apt-get update && apt-get install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/*

# Install uv globally (Node/npm not available at this layer — added by the features layer)
RUN pip install --no-cache-dir uv
