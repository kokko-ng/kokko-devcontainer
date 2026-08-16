"""Post-generation surgery and the closing instructions.

Only two things happen here that Jinja could not do inline:

  * The bundled Claude settings.json is edited as JSON rather than templated.
    Keeping that file free of Jinja is deliberate — it stays valid JSON at
    rest, so `check-json`, `jq`, and tests/merge-settings-tests.sh all run
    against the template itself with no rendering step.
  * The base image digest pin only matches the default Python version, so a
    non-default choice earns a warning rather than a silently wrong pin.
"""

import json
import os
import sys

CLAUDE_PLUGIN_ROSTER = "{{ cookiecutter.claude_plugin_roster }}"
PYTHON_VERSION = "{{ cookiecutter.python_version }}"
PROJECT_SLUG = "{{ cookiecutter.project_slug }}"
CONTAINER_NAME = "{{ cookiecutter.__container_name }}"

# The Dockerfile's FROM line pins a digest that belongs to this tag only.
PINNED_PYTHON_VERSION = "3.12"

SETTINGS = os.path.join(".devcontainer", "config", "claude", "settings.json")

notes = []


def clear_plugin_roster():
    """Ship Claude Code with no marketplaces and no plugins."""
    with open(SETTINGS, encoding="utf-8") as handle:
        settings = json.load(handle)
    settings["enabledPlugins"] = {}
    settings["extraKnownMarketplaces"] = {}
    with open(SETTINGS, "w", encoding="utf-8") as handle:
        json.dump(settings, handle, indent=2)
        handle.write("\n")


if CLAUDE_PLUGIN_ROSTER == "none":
    clear_plugin_roster()
    notes.append(
        "Claude Code ships with an empty plugin roster. Add marketplaces and\n"
        "    plugins to .devcontainer/config/claude/settings.json, then run\n"
        "    'bash .devcontainer/post-create.sh --config-only' to install them."
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
    cd /path/to/your-project && code .

  Read {PROJECT_SLUG}/DEVCONTAINER.md for what is installed and how to change it.
"""
)

for note in notes:
    print(f"  NOTE: {note}\n", file=sys.stderr)
