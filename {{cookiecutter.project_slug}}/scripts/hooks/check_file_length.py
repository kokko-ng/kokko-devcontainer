"""Fail if a tracked file is longer than its limit.

A long file is one that has taken on more than one job. Ruff has no file-length rule, so
this check reads the limits from ``[tool.quality.file-length]`` in pyproject.toml, lists
the tracked files with ``git ls-files``, and reports every file over the limit for its
kind. The fix is to split the file along a real seam, not to raise the limit:
scripts/hooks/check_strictness.py fails the build if a limit is raised.

Globs follow ``fnmatch`` on the repository-relative path, so ``*`` also matches ``/``.
A file that matches a test glob is judged as a test, any other match as source, and a
file that matches an exclude glob (generated code) is not judged at all.
"""

from __future__ import annotations

import subprocess
import sys
from fnmatch import fnmatch
from pathlib import Path
from typing import NamedTuple

from scripts.hooks.tables import load_pyproject, number, str_list, table

ROOT = Path(__file__).resolve().parents[2]


class FileLengthConfig(NamedTuple):
    """The ``[tool.quality.file-length]`` table: limits and the globs that select them."""

    source_max_lines: int
    test_max_lines: int
    source_globs: list[str]
    test_globs: list[str]
    exclude: list[str]


def load_config(root: Path) -> FileLengthConfig | str:
    """Return the limits from pyproject.toml, or a message saying why they cannot be read."""
    config = load_pyproject(root)
    if isinstance(config, str):
        return config
    lengths = table(config, "tool", "quality", "file-length")
    source_max = number(lengths.get("source_max_lines"))
    test_max = number(lengths.get("test_max_lines"))
    source_globs = str_list(lengths.get("source_globs"))
    test_globs = str_list(lengths.get("test_globs"))
    exclude = str_list(lengths.get("exclude", []))
    if source_max is None or test_max is None or source_globs is None or test_globs is None:
        return "pyproject.toml [tool.quality.file-length] needs limits and globs of the right type"
    if exclude is None:
        return "pyproject.toml [tool.quality.file-length] exclude must be a list of globs"
    return FileLengthConfig(int(source_max), int(test_max), source_globs, test_globs, exclude)


def tracked_files(root: Path) -> list[str]:
    """Return the repository-relative paths git tracks, as POSIX paths."""
    # Fixed argument list, no shell, no external input.
    result = subprocess.run(
        ["git", "ls-files", "-z"],  # noqa: S607 -- git is resolved from PATH, as in the other hooks
        check=True,
        capture_output=True,
        text=True,
        cwd=root,
    )
    return [path for path in result.stdout.split("\0") if path]


def limit_for(path: str, config: FileLengthConfig) -> int | None:
    """Return the line limit that applies to the path, or None if the path is not judged."""
    if any(fnmatch(path, pattern) for pattern in config.exclude):
        return None
    if any(fnmatch(path, pattern) for pattern in config.test_globs):
        return config.test_max_lines
    if any(fnmatch(path, pattern) for pattern in config.source_globs):
        return config.source_max_lines
    return None


def line_count(path: Path) -> int | None:
    """Return the number of lines in the file, or None if it is not on disk."""
    try:
        return len(path.read_bytes().splitlines())
    except FileNotFoundError:
        return None  # tracked but deleted in the working tree: nothing to measure


def check_files(root: Path, config: FileLengthConfig, files: list[str]) -> list[str]:
    """Return one message for every file in ``files`` that is over its limit."""
    errors: list[str] = []
    for name in files:
        limit = limit_for(name, config)
        if limit is None:
            continue
        lines = line_count(root / name)
        if lines is not None and lines > limit:
            errors.append(f"{name}: {lines} lines, limit {limit}")
    return errors


def main() -> int:
    """Return 1 with a report if any tracked file is over its limit or the limits are unreadable."""
    config = load_config(ROOT)
    if isinstance(config, str):
        sys.stderr.write(f"{config}\n")
        return 1
    errors = check_files(ROOT, config, tracked_files(ROOT))
    if not errors:
        return 0
    sys.stderr.write("Files over the length limit:\n")
    for error in errors:
        sys.stderr.write(f"  - {error}\n")
    sys.stderr.write(
        "Split the file along a real seam into modules with a purpose of their own, "
        "not the limit.\n"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
