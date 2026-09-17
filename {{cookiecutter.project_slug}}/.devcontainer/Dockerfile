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

# Install uv and pre-commit globally, pinned (npm/node not available yet - added
# by features layer). pre-commit lives in the image rather than being left to
# each project's dev dependencies because the bundled CLAUDE.md makes running
# it non-negotiable: a project that does not list it still gets working hooks
# from this copy (post-create.sh prefers the project's own pin when there is
# one, and falls back to this).
# NOTE: Dependabot cannot see these pins (its docker ecosystem only bumps FROM
# digests) — check for newer versions manually; see MANAGING.md -> Pin audit.
RUN pip install --no-cache-dir uv==0.12.1 pre-commit==4.6.2

# Fail piped RUN commands if any pipeline stage fails (hadolint DL4006).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

{% if cookiecutter.include_azure_sql_driver == "yes" -%}
# Install ODBC Driver 18 for SQL Server (required by pyodbc for Azure SQL),
# jq (a HARD dependency of post-create.sh — the settings merge, roster prune,
# and plugin bootstrap all parse JSON with it), fzf + fd-find for the bundled
# shell config, shellcheck (agents write a lot of shell — lint it where it
# runs), and bubblewrap + socat (the Linux dependencies of Claude Code's Bash
# sandbox, shipped switched off in the bundled settings.json and turned on
# with /sandbox).
# The Debian version/codename for the MS repo is derived from the base image's
# /etc/os-release rather than hardcoded, so a base-image bump (e.g. bookworm ->
# trixie) cannot silently leave the ODBC repo pointing at the wrong release.
# hadolint ignore=DL3008,SC1091
RUN . /etc/os-release \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/${VERSION_ID}/prod ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 unixodbc-dev jq fzf fd-find shellcheck bubblewrap socat \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
{%- else -%}
# jq is a HARD dependency of post-create.sh — the settings merge, roster prune,
# and plugin bootstrap all parse JSON with it. fzf + fd-find back the bundled
# shell config. shellcheck: agents write a lot of shell — lint it where it
# runs. bubblewrap + socat: the Linux dependencies of Claude Code's Bash
# sandbox, shipped switched off in the bundled settings.json and turned on
# with /sandbox.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends jq fzf fd-find shellcheck bubblewrap socat \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
{%- endif %}

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

# Claude Code native binary, PINNED and baked into the image, so every rebuild
# neither re-downloads it in post-create nor picks up whatever happens to be
# the latest release that day: two rebuilds produce the same agent, which is
# the same reason the base image is digest-pinned. DISABLE_AUTOUPDATER=1 in
# devcontainer.json's containerEnv keeps the binary at this version between
# rebuilds; the `cu` alias installs the latest release on demand until the
# next rebuild. Bump the pin here — Dependabot cannot see it (MANAGING.md ->
# Pin audit). It needs no node — the installer drops a standalone binary in
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
# hadolint ignore=DL3066
USER vscode
RUN curl -fsSL https://claude.ai/install.sh | bash -s 2.1.274
# Devcontainer features and any later build steps expect to run as root
# (remoteUser=vscode handles the runtime switch).
# hadolint ignore=DL3002,DL3066
USER root
