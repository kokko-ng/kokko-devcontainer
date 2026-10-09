"""Fail if a test cannot fail.

A test with no assertion passes whatever the code does, and it still counts
towards coverage. This check requires every ``test_*`` function to contain at
least one real assertion, and rejects assertions that are always true.

Accepted as an assertion: an ``assert`` statement, ``pytest.raises``,
``pytest.warns``, ``pytest.deprecated_call``, ``pytest.fail``, and calls to
functions or methods whose name starts with ``assert``.
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "tests"
PYTEST_CHECKS = frozenset({"raises", "warns", "deprecated_call", "fail"})


def _call_name(node: ast.Call) -> str:
    """Return the final name of the called function, for example ``raises``."""
    target = node.func
    if isinstance(target, ast.Attribute):
        return target.attr
    if isinstance(target, ast.Name):
        return target.id
    return ""


def _is_pytest_check(node: ast.Call) -> bool:
    """Return True for ``pytest.raises(...)`` and the other pytest assertion helpers."""
    target = node.func
    return (
        isinstance(target, ast.Attribute)
        and isinstance(target.value, ast.Name)
        and target.value.id == "pytest"
        and target.attr in PYTEST_CHECKS
    )


def _always_true(test: ast.expr) -> bool:
    """Return True for an assertion that no behaviour of the code could make fail."""
    if isinstance(test, ast.Constant):
        return bool(test.value)
    if isinstance(test, ast.UnaryOp) and isinstance(test.op, ast.Not):
        return isinstance(test.operand, ast.Constant) and not test.operand.value
    if isinstance(test, ast.Compare) and len(test.ops) == 1 and len(test.comparators) == 1:
        same = ast.dump(test.left) == ast.dump(test.comparators[0])
        return same and isinstance(test.ops[0], (ast.Eq, ast.Is, ast.LtE, ast.GtE))
    return False


def check_function(function: ast.FunctionDef | ast.AsyncFunctionDef) -> list[str]:
    """Return the problems found in one test function."""
    problems = []
    real_assertions = 0
    for node in ast.walk(function):
        if isinstance(node, ast.Assert):
            if _always_true(node.test):
                problems.append(f"line {node.lineno}: assertion is always true")
            else:
                real_assertions += 1
        elif isinstance(node, ast.Call) and (
            _is_pytest_check(node) or _call_name(node).startswith("assert")
        ):
            real_assertions += 1
    if real_assertions == 0:
        problems.append(f"line {function.lineno}: test '{function.name}' asserts nothing")
    return problems


def check_file(path: Path) -> list[str]:
    """Return the problems found in one test module."""
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    relative = path.relative_to(ROOT)
    return [
        f"{relative}: {problem}"
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef | ast.AsyncFunctionDef)
        and node.name.startswith("test_")
        for problem in check_function(node)
    ]


def main() -> int:
    """Check every test module and return a process exit code."""
    problems = [
        problem for path in sorted(TESTS.rglob("test_*.py")) for problem in check_file(path)
    ]
    if not problems:
        return 0
    sys.stderr.write("Tests that cannot fail:\n")
    for problem in problems:
        sys.stderr.write(f"  {problem}\n")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
