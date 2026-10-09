"""Command-line entry point: ``uv run python -m {{ cookiecutter.__package_name }}``.

The container puts ``{{ cookiecutter.backend_src_dir }}/`` on ``PYTHONPATH``; elsewhere, set it first.

A starting point so the quality gate has typed, tested code to check from the first
commit. Replace it with the real application.
"""

import sys

PROJECT_NAME = {{ cookiecutter.project_name | tojson }}


def main() -> int:
    """Write the project's name to standard output and return the exit status."""
    sys.stdout.write(f"{PROJECT_NAME}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
