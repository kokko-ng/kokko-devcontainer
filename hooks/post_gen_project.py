"""Post-generation surgery and the closing instructions.

Only two things happen here that Jinja could not do inline:

  * The bundled Claude settings.json is edited as JSON rather than templated:
    the plugin roster is emptied on request, and the attribution override is
    removed when Claude Code should sign its commits. Keeping that file free
    of Jinja is deliberate — it stays valid JSON at rest, so `check-json`,
    `jq`, and tests/merge-settings-tests.sh all run against the template
    itself with no rendering step.
  * The base image digest pin only matches the default Python version, so a
    non-default choice earns a warning rather than a silently wrong pin.
"""

import json
import os
import sys

CLAUDE_PLUGIN_ROSTER = "{{ cookiecutter.claude_plugin_roster }}"
CLAUDE_ATTRIBUTION = "{{ cookiecutter.claude_attribution }}"
INCLUDE_DOCKER_IN_DOCKER = "{{ cookiecutter.include_docker_in_docker }}"
PYTHON_VERSION = "{{ cookiecutter.python_version }}"
PROJECT_SLUG = "{{ cookiecutter.project_slug }}"
CONTAINER_NAME = "{{ cookiecutter.__container_name }}"

# The Dockerfile's FROM line pins a digest that belongs to this tag only.
PINNED_PYTHON_VERSION = "3.14"

SETTINGS = os.path.join(".devcontainer", "config", "claude", "settings.json")

notes = []


def clear_plugin_roster(settings):
    """Ship Claude Code with no marketplaces and no plugins."""
    settings["enabledPlugins"] = {}
    settings["extraKnownMarketplaces"] = {}


def enable_claude_attribution(settings):
    """Let Claude Code sign the commits and pull requests it makes.

    The bundle ships `attribution` as empty strings, which hides the
    Co-Authored-By trailer and the PR footer. Removing the key restores Claude
    Code's own default text rather than copying that text here, so the wording
    follows the CLI instead of this template. merge-settings.jq only adds
    `attribution` when it is absent, so a container provisioned by an older
    bundle keeps its empty strings until they are removed by hand.
    """
    settings.pop("attribution", None)


settings_edits = []

if CLAUDE_PLUGIN_ROSTER == "none":
    settings_edits.append(clear_plugin_roster)
    notes.append(
        "Claude Code ships with an empty plugin roster. Add marketplaces and\n"
        "    plugins to .devcontainer/config/claude/settings.json, then run\n"
        "    'bash .devcontainer/post-create.sh --config-only' to install them."
    )

if CLAUDE_ATTRIBUTION == "yes":
    settings_edits.append(enable_claude_attribution)

if settings_edits:
    # One read and one write, however many answers touch the file, so the
    # edits compose instead of each rewriting the other's output.
    with open(SETTINGS, encoding="utf-8") as handle:
        bundled_settings = json.load(handle)
    for settings_edit in settings_edits:
        settings_edit(bundled_settings)
    with open(SETTINGS, "w", encoding="utf-8") as handle:
        json.dump(bundled_settings, handle, indent=2)
        handle.write("\n")

if INCLUDE_DOCKER_IN_DOCKER == "yes":
    notes.append(
        "Docker-in-Docker makes the container PRIVILEGED (the feature requires it).\n"
        "    An agent running in it without prompts then has, in effect, root on the\n"
        "    Colima VM, including every other project's containers and volumes. Keep\n"
        "    that in mind when deciding what runs in this container unattended."
    )

if PYTHON_VERSION != PINNED_PYTHON_VERSION:
    notes.append(
        f"The base image is pinned by digest for Python {PINNED_PYTHON_VERSION} only, so the\n"
        f"    Python {PYTHON_VERSION} FROM line carries a tag and no digest. Pin it yourself for\n"
        "    reproducible builds:\n"
        f"      docker pull mcr.microsoft.com/devcontainers/python:{PYTHON_VERSION}-bookworm\n"
        "      docker images --digests mcr.microsoft.com/devcontainers/python"
    )

print(
    f"""
Generated {PROJECT_SLUG}/ — container name: {CONTAINER_NAME}

  Starting a new project
    cd {PROJECT_SLUG}
    code .            # then accept "Reopen in Container"

  Adding this to an existing project
    cp -r {PROJECT_SLUG}/.devcontainer /path/to/your-project/
    cp {PROJECT_SLUG}/CLAUDE.md /path/to/your-project/     # or merge into yours
    cat {PROJECT_SLUG}/.gitignore >> /path/to/your-project/.gitignore
    cd /path/to/your-project && code .

  Read {PROJECT_SLUG}/DEVCONTAINER.md for what is installed and how to change it.
"""
)

for note in notes:
    print(f"  NOTE: {note}\n", file=sys.stderr)
