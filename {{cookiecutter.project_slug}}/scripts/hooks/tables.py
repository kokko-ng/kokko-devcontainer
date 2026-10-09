"""Typed access to the TOML and JSON settings the hook scripts read.

``tomllib`` and ``json`` return untyped data. These helpers narrow it at the boundary,
so a setting of the wrong type reads as absent (and fails the check that needs it)
rather than as if it were right. Standard library only: the hooks run under any
``python3`` from 3.11, before the project environment exists.
"""

from __future__ import annotations

import tomllib
from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from pathlib import Path

Table = dict[str, object]


def as_table(value: object) -> Table:
    """Return the value as a table, or an empty table if it is not one."""
    if isinstance(value, dict):
        return cast("Table", value)
    return {}


def table(root: Table, *keys: str) -> Table:
    """Return the nested table at ``keys``, or an empty table if any step is missing."""
    node = root
    for key in keys:
        node = as_table(node.get(key))
    return node


def items(value: object) -> list[object]:
    """Return the value as a list, or an empty list if it is not one."""
    if isinstance(value, list):
        return cast("list[object]", value)
    return []


def str_list(value: object) -> list[str] | None:
    """Return the value as a list of strings, or None if it is anything else."""
    if not isinstance(value, list):
        return None
    entries = items(value)
    strings = [entry for entry in entries if isinstance(entry, str)]
    return strings if len(strings) == len(entries) else None


def number(value: object) -> float | None:
    """Return an integer or float setting as a float, or None for any other type."""
    if isinstance(value, bool) or not isinstance(value, int | float):
        return None
    return float(value)


def load_pyproject(root: Path) -> Table | str:
    """Return pyproject.toml as a table, or a message saying why it cannot be read."""
    path = root / "pyproject.toml"
    try:
        return cast("Table", tomllib.loads(path.read_text(encoding="utf-8")))
    except (OSError, ValueError) as error:  # tomllib.TOMLDecodeError is a ValueError
        return f"pyproject.toml cannot be read: {error}"
