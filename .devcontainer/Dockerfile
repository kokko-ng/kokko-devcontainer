# Base image pinned by digest for reproducible builds. The tag is kept for
# readability; the digest is what the build resolves. Dependabot (docker
# ecosystem) proposes digest bumps.
FROM mcr.microsoft.com/devcontainers/python:3.12-bookworm@sha256:d4ffe02682e0960406fc66f500eb7a299a9caae3a47621da3d17dc969c09bb69

# Install uv globally, pinned (npm/node not available yet - added by features layer)
RUN pip install --no-cache-dir uv==0.12.1

# Install ODBC Driver 18 for SQL Server (required by pyodbc for Azure SQL),
# jq (a HARD dependency of the git safety hooks — without it they cannot parse
# tool payloads), and fzf + fd-find for the bundled shell config.
# hadolint ignore=DL3008
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 unixodbc-dev jq fzf fd-find \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create host-path symlink so macOS absolute paths in Claude plugin configs
# (e.g. /Users/<username>/.claude/...) resolve inside the container.
# The actual username is injected at build time by devcontainer.json via
# ${localEnv:USER}; the default covers direct `docker build` AND an empty
# build arg (an unset localEnv:USER arrives as "").
ARG HOST_USER=vscode
RUN HU="${HOST_USER:-vscode}"; mkdir -p /Users && ln -sfn /home/vscode "/Users/$HU"

# Install host CA certificates so curl/npm/pip trust corporate proxies.
# certs/ always exists in git (.gitkeep), so plain `docker build` works even
# before init-host-certs.sh has populated it.
COPY certs/ /usr/local/share/ca-certificates/host/
RUN update-ca-certificates
