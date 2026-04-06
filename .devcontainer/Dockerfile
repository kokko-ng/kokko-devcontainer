FROM mcr.microsoft.com/devcontainers/python:3.12-bookworm

# Trust host CA certificates (e.g. corporate proxy CAs)
# Extracted from the host by initializeCommand (init-host-certs.sh)
COPY certs/ /usr/local/share/ca-certificates/extra/
RUN update-ca-certificates
# Node.js uses its own CA bundle; point it at the system store so it trusts
# corporate proxy CAs too (needed by Claude Code installer, npm, etc.)
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# jq is required by kokko-cmds plugin hooks (JSON parsing of hook input).
# Chromium is installed for the Playwright MCP plugin. Google Chrome is not
# available for ARM64 Linux, so we use the system Chromium package instead.
# The Playwright MCP looks for the 'chrome' channel at /opt/google/chrome/chrome
# on Linux — the symlink below satisfies that lookup without Google Chrome.
RUN apt-get update && apt-get install -y --no-install-recommends \
        jq \
        chromium \
        chromium-sandbox \
        libnss3 \
        libatk-bridge2.0-0 \
        libgtk-3-0 \
        libgbm1 \
        libasound2 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/google/chrome \
    && ln -sf /usr/bin/chromium /opt/google/chrome/chrome

# Install uv globally (Node/npm not available at this layer — added by the features layer)
RUN pip install --no-cache-dir --root-user-action=ignore uv
