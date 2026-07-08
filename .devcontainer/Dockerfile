FROM mcr.microsoft.com/devcontainers/python:3.12-bookworm

# Install uv globally (npm/node not available yet - added by features layer)
RUN pip install --no-cache-dir uv

# Install ODBC Driver 18 for SQL Server (required by pyodbc for Azure SQL)
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 unixodbc-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && true

# Create host-path symlink so macOS absolute paths in Claude plugin configs
# (e.g. /Users/<username>/.claude/...) resolve inside the container.
# The actual username is injected at build time by devcontainer.json via
# ${localEnv:USER}; the default is a placeholder for direct `docker build`.
ARG HOST_USER=vscode
RUN mkdir -p /Users && ln -sfn /home/vscode /Users/${HOST_USER}

# Install host CA certificates so curl/npm/pip trust corporate proxies
COPY certs/ /usr/local/share/ca-certificates/host/
RUN update-ca-certificates
