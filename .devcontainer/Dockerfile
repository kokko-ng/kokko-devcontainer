FROM mcr.microsoft.com/devcontainers/python:3.12-bookworm

# Trust host CA certificates (e.g. corporate proxy CAs)
# Extracted from the host by initializeCommand (init-host-certs.sh)
COPY certs/ /usr/local/share/ca-certificates/extra/
RUN update-ca-certificates
# Node.js uses its own CA bundle; point it at the system store so it trusts
# corporate proxy CAs too (needed by Claude Code installer, npm, etc.)
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# jq is required by kokko-cmds plugin hooks (JSON parsing of hook input)
RUN apt-get update && apt-get install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/*

# Install uv globally (Node/npm not available at this layer — added by the features layer)
RUN pip install --no-cache-dir uv
