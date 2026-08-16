"""Validate the answers before anything is written to disk.

Cookiecutter renders this file with Jinja first, so the answers arrive as
literals. Failing here (exit 1) aborts generation and leaves no half-written
project behind, which is why every check that can reject an answer lives in
this hook rather than in post_gen_project.py.
"""

import re
import sys

SLUG = "{{ cookiecutter.project_slug }}"
BACKEND_SRC_DIR = "{{ cookiecutter.backend_src_dir }}"
FRONTEND_DIR = "{{ cookiecutter.frontend_dir }}"
BACKEND_PORT = "{{ cookiecutter.backend_port }}"
FRONTEND_PORT = "{{ cookiecutter.frontend_port }}"

# The slug becomes a directory name, the container name, and (for
# cache_volume_scope=per-project) a Docker volume name. Docker volume names
# accept [a-zA-Z0-9][a-zA-Z0-9_.-]*; lowercase-and-dashes is the safe subset
# that is also a sane directory name.
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")

errors = []

if not SLUG_RE.match(SLUG):
    errors.append(
        f"project_slug {SLUG!r} must be lowercase letters, digits and dashes, "
        "starting with a letter or digit (it names a directory, the container "
        "and, optionally, Docker volumes)"
    )


def check_relative_dir(label, value):
    if not value:
        errors.append(f"{label} must not be empty")
        return
    if value.startswith("/"):
        errors.append(f"{label} {value!r} must be relative to the workspace, not absolute")
    if ".." in value.split("/"):
        errors.append(f"{label} {value!r} must not escape the workspace with '..'")


check_relative_dir("backend_src_dir", BACKEND_SRC_DIR)
check_relative_dir("frontend_dir", FRONTEND_DIR)


def check_port(label, value):
    try:
        port = int(value)
    except ValueError:
        errors.append(f"{label} {value!r} is not a number")
        return None
    # Below 1024 the container user cannot bind without extra capabilities,
    # so a low port would fail at run time rather than here.
    if not 1024 <= port <= 65535:
        errors.append(f"{label} {port} must be between 1024 and 65535")
        return None
    return port


backend = check_port("backend_port", BACKEND_PORT)
frontend = check_port("frontend_port", FRONTEND_PORT)

if backend is not None and backend == frontend:
    errors.append(
        f"backend_port and frontend_port are both {backend}; "
        "two services cannot forward the same port"
    )

if errors:
    print("Cannot generate the devcontainer:\n", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    print("", file=sys.stderr)
    sys.exit(1)
