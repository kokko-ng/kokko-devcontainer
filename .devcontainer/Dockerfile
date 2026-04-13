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

# Install Chromium and system dependencies for Playwright.
# The Playwright MCP server hardcodes the chrome binary path to
# /opt/google/chrome/chrome, so symlink the Debian chromium binary there.
# (Google Chrome itself is x86_64-only and unavailable on arm64.)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        chromium \
        libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
        libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 \
        libxrandr2 libgbm1 libasound2 libpango-1.0-0 libpangocairo-1.0-0 \
    && mkdir -p /opt/google/chrome \
    && ln -sf /usr/bin/chromium /opt/google/chrome/chrome \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create host-path symlink so macOS absolute paths in Claude plugin configs
# (e.g. /Users/kng1/.claude/...) resolve inside the container.
# The actual username is injected at build time via ARG; defaults to kng1.
ARG HOST_USER=kng1
RUN mkdir -p /Users && ln -sfn /home/vscode /Users/${HOST_USER}

# Install host CA certificates so curl/npm/pip trust corporate proxies
COPY certs/ /usr/local/share/ca-certificates/host/
RUN update-ca-certificates
