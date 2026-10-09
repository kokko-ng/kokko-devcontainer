{% if cookiecutter.python_version == "3.14" -%}
# Base image pinned by digest for reproducible builds. The tag is kept for
# readability; the digest is what the build resolves. Dependabot (docker
# ecosystem) proposes digest bumps.
FROM mcr.microsoft.com/devcontainers/python:3.14-bookworm@sha256:29f5e05ad69bdec17b27b353b034000a7b9fecf7bd29b759e16954ab059ee46d
{%- else -%}
# NOT pinned by digest: the template only carries a digest for its default
# Python (3.14), and inventing one for {{ cookiecutter.python_version }} would be worse than none. Pin it
# yourself for reproducible builds — see DEVCONTAINER.md -> Pinning the base image.
FROM mcr.microsoft.com/devcontainers/python:{{ cookiecutter.python_version }}-bookworm
{%- endif %}

# The image is linux/arm64 on Apple Silicon (native, not emulated). OpenSSL's
# CPU-capability probe there can hit an instruction the VM traps, and az,
# Python's cryptography and anything else that loads libcrypto die with
# "Illegal instruction". 0 skips the probe (generic code paths); x86 builds
# ignore it. Set before the first RUN so the build's own az and pip use it.
ENV OPENSSL_armcap=0

# Install uv and pre-commit globally, pinned (npm/node not available yet - added
# by features layer). pre-commit lives in the image rather than being left to
# each project's dev dependencies because the bundled CLAUDE.md makes running
# it non-negotiable: a project that does not list it still gets working hooks
# from this copy (post-create.sh prefers the project's own pin when there is
# one, and falls back to this).
# NOTE: Dependabot cannot see these pins (its docker ecosystem only bumps FROM
# digests) — check for newer versions manually; see upstream docs/maintenance.md -> Pin audit.
#
# The base image also puts pytest, mypy, black, flake8, pylint and other dev
# tools on PATH from /usr/local/py-utils. `uv run pytest` in a project without
# pytest then runs that global copy outside the project's environment and fails
# with a misleading "No module named ..." for the project's own imports. Without
# them it fails plainly ("Failed to spawn: pytest"); projects bring their own.
RUN pip install --no-cache-dir uv==0.12.1 pre-commit==4.6.2 \
    && for t in pytest py.test mypy mypyc dmypy stubgen stubtest black blackd flake8 \
        pylint pylint-config pyreverse symilar autopep8 yapf yapf-diff pycodestyle \
        pydocstyle bandit bandit-baseline bandit-config-generator; do \
        rm -f "/usr/local/py-utils/bin/$t"; \
    done

# Fail piped RUN commands if any pipeline stage fails (hadolint DL4006).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

{% if cookiecutter.include_azure_sql_driver == "yes" -%}
# Install ODBC Driver 18 for SQL Server (required by pyodbc for Azure SQL),
# jq (a HARD dependency of post-create.sh — the settings merge, roster prune,
# and plugin bootstrap all parse JSON with it), fzf + fd-find for the bundled
# shell config, shellcheck (agents write a lot of shell — lint it where it
# runs), bubblewrap + socat (the Linux dependencies of Claude Code's Bash
# sandbox, which the managed policy keeps off: bubblewrap cannot run in an
# unprivileged container), and the outbound firewall's iptables, ipset, dig,
# ip and dnsmasq (its resolver, which adds allowlisted addresses as they are
# looked up).
# The Debian version/codename for the MS repo is derived from the base image's
# /etc/os-release rather than hardcoded, so a base-image bump (e.g. bookworm ->
# trixie) cannot silently leave the ODBC repo pointing at the wrong release.
# hadolint ignore=DL3008,SC1091
RUN . /etc/os-release \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/${VERSION_ID}/prod ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 unixodbc-dev jq fzf fd-find shellcheck bubblewrap socat iptables ipset dnsutils iproute2 dnsmasq-base \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
{%- else -%}
# jq is a HARD dependency of post-create.sh — the settings merge, roster prune,
# and plugin bootstrap all parse JSON with it. fzf + fd-find back the bundled
# shell config. shellcheck: agents write a lot of shell — lint it where it
# runs. bubblewrap + socat: the Linux dependencies of Claude Code's Bash
# sandbox, which the managed policy keeps off (bubblewrap cannot run in an
# unprivileged container). iptables, ipset, dig, ip and dnsmasq: the outbound
# firewall and its resolver, which adds allowlisted addresses as they are
# looked up.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends jq fzf fd-find shellcheck bubblewrap socat iptables ipset dnsutils iproute2 dnsmasq-base \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
{%- endif %}

{% if cookiecutter.include_playwright == "yes" -%}
# The system libraries Playwright's Chromium needs (`playwright install-deps
# chromium` on Debian 12, same package names on arm64 and x64), in the image
# rather than at provision time: the browsers live in a shared volume, so a
# new container on a warm volume would otherwise skip the download step that
# used to pull these in, and every launch would fail on missing libraries.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcairo2 libcups2 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 libfontconfig1 libfreetype6 fonts-liberation \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

{% endif -%}
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

# Claude Code policy (deny list, bypass lock), root-owned in the image.
# post-create.sh removes the container user's sudo after provisioning, so an
# agent cannot rewrite it; a policy change takes a rebuild, which only you run.
COPY config/claude/managed-settings.json /etc/claude-code/managed-settings.json

# Outbound firewall (firewall/init-firewall.sh): root-owned script and
# allowlist, and the one thing the container user may still run through sudo
# once post-create.sh has removed the rest. It only rebuilds the same rules.
COPY firewall/init-firewall.sh /usr/local/sbin/devcontainer-firewall
COPY firewall/allowed-domains.txt /etc/devcontainer/allowed-domains.txt
RUN chmod 0755 /usr/local/sbin/devcontainer-firewall \
    && chmod 0644 /etc/devcontainer/allowed-domains.txt \
    && echo 'vscode ALL=(root) NOPASSWD: /usr/local/sbin/devcontainer-firewall' > /etc/sudoers.d/devcontainer-firewall \
    && chmod 0440 /etc/sudoers.d/devcontainer-firewall

# Starship prompt, PINNED: the static musl build from the release page, picked
# by architecture (aarch64 on Apple Silicon hosts, x86_64 on CI). The bundled
# zsh config falls back to an Oh My Zsh theme when the binary is absent, so an
# image built before this layer still gets a prompt. Placed after the CA layer
# so the download trusts corporate-proxy certs. Dependabot cannot see this pin
# (upstream docs/maintenance.md -> Pin audit).
RUN curl -fsSL "https://github.com/starship/starship/releases/download/v1.26.0/starship-$(uname -m)-unknown-linux-musl.tar.gz" \
    | tar -xz -C /usr/local/bin starship \
    && starship --version

{% if cookiecutter.include_azure_cli == "yes" -%}
# Bicep CLI, PINNED and picked by architecture (arm64 on Apple Silicon, x64 on
# CI), so `az bicep` and `az deployment ... --template-file *.bicep` work
# without az downloading its own copy on first use. The
# AZURE_BICEP_* settings make az use this binary from PATH and skip its
# release check. Telemetry is off so its refused upload does not crowd
# `devcontainer-firewall --blocked`. Dependabot cannot see this pin (upstream
# docs/maintenance.md -> Pin audit).
ARG BICEP_VERSION=v0.48.1
RUN case "$(dpkg --print-architecture)" in arm64) arch=arm64 ;; *) arch=x64 ;; esac \
    && curl -fsSL -o /usr/local/bin/bicep "https://github.com/Azure/bicep/releases/download/${BICEP_VERSION}/bicep-linux-${arch}" \
    && chmod 0755 /usr/local/bin/bicep \
    && bicep --version
ENV AZURE_BICEP_USE_BINARY_FROM_PATH=true \
    AZURE_BICEP_CHECK_VERSION=false \
    AZURE_CORE_COLLECT_TELEMETRY=false
# Azure CLI extensions live in the image, not in ~/.azure: that is a shared
# sign-in volume mounted over the home directory, which would hide anything
# installed there at build time. The azure-cli feature (devcontainer.json)
# installs the extensions it lists into this directory as vscode, so
# `az extension add/update` keeps working at runtime.
ENV AZURE_EXTENSION_DIR=/usr/local/lib/azure-cli-extensions
RUN install -d -o vscode -g vscode -m 0755 "$AZURE_EXTENSION_DIR"

{% endif -%}
# Claude Code native binary, baked into the image. `dev` passes the host's
# version (DEVCONTAINER_CLAUDE_VERSION -> CLAUDE_CODE_VERSION), so the
# container runs the same Claude Code as the Mac, and updates an existing
# container to it when the Mac moves ahead. Built without `dev` (VS Code's
# Reopen in Container), it falls back to the pin below, so two such rebuilds
# still produce the same agent. DISABLE_AUTOUPDATER=1 in containerEnv keeps
# the binary put between rebuilds; `cu` installs the latest on demand. Bump
# the pin here — Dependabot cannot see it (upstream docs/maintenance.md -> Pin audit). It needs no node — the installer drops a standalone binary in
# ~/.local/bin, owned by vscode, hence the USER switch. Placed after the CA
# layer so corporate-proxy certs are already trusted. post-create.sh keeps its
# `command -v claude` fallback for images built before this layer existed. The
# npm-based CLIs (copilot, playwright) CANNOT move here: node arrives via a
# devcontainer feature, which layers after this Dockerfile.
#
# DL3066 (non-numeric user-id) is ignored on both USER lines below. `vscode` is
# the account the devcontainer base image creates, and devcontainer.json's
# `remoteUser` names it as a string — hardcoding its uid here would duplicate a
# mapping the base image owns and silently rot when that image changes it.
ARG CLAUDE_CODE_VERSION
# hadolint ignore=DL3066
USER vscode
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION:-2.1.295}"
# Devcontainer features and any later build steps expect to run as root
# (remoteUser=vscode handles the runtime switch).
# hadolint ignore=DL3002,DL3066
USER root
