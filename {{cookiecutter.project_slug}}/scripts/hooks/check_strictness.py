"""Fail if a quality gate has been loosened.

Strict typing, the complexity ceiling, the file-length limits, the coverage floor, and
the lint rule selection are repository rules. This check exists so a rule cannot be
satisfied by quietly weakening the configuration it is measured against.

Standard library only, so it runs under any ``python3`` before the project environment
exists. Run it as a module from the repository root:
``python3 -m scripts.hooks.check_strictness``.
"""

from __future__ import annotations

import json
import re
import shlex
import sys
from pathlib import Path
from typing import NamedTuple

from scripts.hooks.layout import BACKEND_SRC_DIR, FRONTEND_DIR, PACKAGE
from scripts.hooks.tables import Table, as_table, items, load_pyproject, number, str_list, table

ROOT = Path(__file__).resolve().parents[2]

REQUIRED_MYPY_TRUE = (
    "strict",
    "warn_unreachable",
    "disallow_any_explicit",
    "disallow_any_unimported",
    "disallow_any_decorated",
)
REQUIRED_MYPY_ERROR_CODES = {
    "ignore-without-code",
    "redundant-expr",
    "truthy-bool",
    "explicit-override",
    "unused-awaitable",
    "mutable-override",
    "narrowed-type-not-subtype",
    "deprecated",
    "exhaustive-match",
    "possibly-undefined",
}
REQUIRED_MYPY_FILES = {BACKEND_SRC_DIR, "tests", "scripts"}
FORBIDDEN_MYPY_KEYS = ("ignore_missing_imports", "ignore_errors", "follow_imports", "exclude")
FIRST_PARTY_OVERRIDES = {"tests.*", "scripts.*", "*"}
REQUIRED_RUFF_RULES = {"ANN", "TC", "PGH", "S", "C90", "D", "ARG", "PT", "ERA"}
FORBIDDEN_GLOBAL_IGNORES = {"S", "D", "C90", "C901", "ANN", "ARG", "PT"}
MAX_COMPLEXITY = 8
MIN_COVERAGE = 95
MIN_VULTURE_CONFIDENCE = 60
MAX_SOURCE_LINES = 400
MAX_TEST_LINES = 500
REQUIRED_SOURCE_GLOBS = {
    f"{BACKEND_SRC_DIR}/*.py",
    "scripts/*.py",
    f"{FRONTEND_DIR}/src/*.ts",
    f"{FRONTEND_DIR}/src/*.vue",
}
REQUIRED_TEST_GLOBS = {"tests/*.py", f"{FRONTEND_DIR}/tests/*.ts"}
ALLOWED_LENGTH_EXCLUDES: set[str] = set()
"""Generated files that may be excluded from the length limits. Add one with a reason."""
ANY_EXPR_HOOK_ID = "mypy-any-expr"
ANY_EXPR_PATHS = (BACKEND_SRC_DIR, "scripts")
FILE_LENGTH_HOOK_ID = "file-length"
STRAY_CONFIG = ("mypy.ini", ".mypy.ini", "setup.cfg", ".flake8", ".isort.cfg", "ruff.toml")
REQUIRED_TS_TRUE = (
    "strict",
    "noUncheckedIndexedAccess",
    "exactOptionalPropertyTypes",
    "noImplicitOverride",
)
ESLINT_CONFIGS = ("eslint.config.js", "eslint.config.mjs", "eslint.config.ts")
ESLINT_COMPLEXITY = re.compile(r"""\bcomplexity\s*:\s*\[\s*["']error["']\s*,\s*(\d+)\s*\]""")
HOOK_ID = re.compile(r"^\s*-\s+id:\s*([\w.-]+)")
HOOK_KEY = re.compile(r"^\s+(entry|pass_filenames):\s*(.*?)\s*$")


class Hook(NamedTuple):
    """One hook of .pre-commit-config.yaml, reduced to what this check reads."""

    entry: str
    pass_filenames: bool


def check_override(override: Table, errors: list[str]) -> None:
    """Append an error for a mypy override of a first-party module."""
    module = override.get("module")
    names = [module] if isinstance(module, str) else str_list(module) or []
    for name in names:
        if name.split(".")[0] == PACKAGE or name in FIRST_PARTY_OVERRIDES:
            errors.append(f"[tool.mypy] override for first-party module '{name}' is forbidden")
        if override.get("ignore_errors") is True and name.count(".") <= 1:
            errors.append(f"[tool.mypy] override '{name}' must not set ignore_errors")


def check_mypy(mypy: Table, errors: list[str]) -> None:
    """Append an error for each way ``[tool.mypy]`` loosens strict typing."""
    errors.extend(
        f"[tool.mypy] {key} must be true" for key in REQUIRED_MYPY_TRUE if mypy.get(key) is not True
    )
    missing_codes = REQUIRED_MYPY_ERROR_CODES - set(str_list(mypy.get("enable_error_code")) or [])
    if missing_codes:
        errors.append(f"[tool.mypy] enable_error_code is missing {sorted(missing_codes)}")
    missing_files = REQUIRED_MYPY_FILES - set(str_list(mypy.get("files")) or [])
    if missing_files:
        errors.append(f"[tool.mypy] files must cover {sorted(missing_files)}")
    errors.extend(
        f"[tool.mypy] {key} is not allowed at the top level"
        for key in FORBIDDEN_MYPY_KEYS
        if key in mypy
    )
    for override in items(mypy.get("overrides")):
        check_override(as_table(override), errors)


def check_ruff(lint: Table, errors: list[str]) -> None:
    """The rule selection and the complexity ceiling must not be loosened."""
    missing_rules = REQUIRED_RUFF_RULES - set(str_list(lint.get("select")) or [])
    if missing_rules:
        errors.append(f"[tool.ruff.lint] select is missing {sorted(missing_rules)}")
    errors.extend(
        f"[tool.ruff.lint] ignore must not disable '{rule}' globally"
        for rule in sorted(set(str_list(lint.get("ignore")) or []) & FORBIDDEN_GLOBAL_IGNORES)
    )
    complexity = number(table(lint, "mccabe").get("max-complexity"))
    if complexity is None or complexity > MAX_COMPLEXITY:
        errors.append(f"[tool.ruff.lint.mccabe] max-complexity must be at most {MAX_COMPLEXITY}")


def check_quality_floors(tool: Table, errors: list[str]) -> None:
    """Coverage floor, branch coverage, dead-code confidence, and deptry must stay."""
    floor = number(table(tool, "coverage", "report").get("fail_under"))
    if floor is None or floor < MIN_COVERAGE:
        errors.append(f"[tool.coverage.report] fail_under must be at least {MIN_COVERAGE}")
    if table(tool, "coverage", "run").get("branch") is not True:
        errors.append("[tool.coverage.run] branch must be true")
    confidence = number(table(tool, "vulture").get("min_confidence"))
    if confidence is None or confidence > MIN_VULTURE_CONFIDENCE:
        errors.append(f"[tool.vulture] min_confidence must be at most {MIN_VULTURE_CONFIDENCE}")
    if "deptry" not in tool:
        errors.append("[tool.deptry] configuration must exist")


def check_file_length_floors(lengths: Table, errors: list[str]) -> None:
    """The file-length limits must not be raised, nor the files they cover narrowed."""
    if not lengths:
        errors.append("[tool.quality.file-length] configuration must exist")
        return
    limits = (("source_max_lines", MAX_SOURCE_LINES), ("test_max_lines", MAX_TEST_LINES))
    for key, ceiling in limits:
        value = number(lengths.get(key))
        if value is None or value > ceiling:
            errors.append(f"[tool.quality.file-length] {key} must be at most {ceiling}")
    globs = set(str_list(lengths.get("source_globs")) or [])
    globs |= set(str_list(lengths.get("test_globs")) or [])
    missing = (REQUIRED_SOURCE_GLOBS | REQUIRED_TEST_GLOBS) - globs
    if missing:
        errors.append(f"[tool.quality.file-length] globs must still cover {sorted(missing)}")
    extra = set(str_list(lengths.get("exclude")) or []) - ALLOWED_LENGTH_EXCLUDES
    if extra:
        errors.append(
            f"[tool.quality.file-length] exclude may list only generated files allowed in "
            f"check_strictness.py, not {sorted(extra)}"
        )


def check_python(errors: list[str]) -> None:
    """Append an error for each way pyproject.toml or a stray config file loosens a gate."""
    config = load_pyproject(ROOT)
    if isinstance(config, str):
        errors.append(config)
        return
    tool = table(config, "tool")
    check_mypy(table(tool, "mypy"), errors)
    check_ruff(table(tool, "ruff", "lint"), errors)
    check_quality_floors(tool, errors)
    check_file_length_floors(table(tool, "quality", "file-length"), errors)
    errors.extend(
        f"{name} must not exist; configure tools in pyproject.toml"
        for name in STRAY_CONFIG
        if (ROOT / name).exists()
    )


def load_hooks(text: str) -> dict[str, Hook]:
    """Return the hooks of .pre-commit-config.yaml by id, read line by line."""
    hooks: dict[str, Hook] = {}
    current: str | None = None
    for line in text.splitlines():
        found = HOOK_ID.match(line)
        if found:
            current = str(found.group(1))
            hooks[current] = Hook(entry="", pass_filenames=True)
            continue
        setting = HOOK_KEY.match(line.split(" #")[0])
        if current is None or setting is None:
            continue
        key, value = str(setting.group(1)), str(setting.group(2))
        if key == "entry":
            hooks[current] = hooks[current]._replace(entry=value)
        else:
            hooks[current] = hooks[current]._replace(pass_filenames=value != "false")
    return hooks


def check_hooks(errors: list[str]) -> None:
    """The no-Any mypy hook and the file-length hook must stay in .pre-commit-config.yaml."""
    path = ROOT / ".pre-commit-config.yaml"
    hooks = load_hooks(path.read_text(encoding="utf-8") if path.exists() else "")
    any_expr = hooks.get(ANY_EXPR_HOOK_ID)
    required = {"mypy", "--disallow-any-expr", *ANY_EXPR_PATHS}
    words = set(shlex.split(any_expr.entry)) if any_expr else set()
    if any_expr is None or any_expr.pass_filenames or not required <= words:
        errors.append(
            f".pre-commit-config.yaml hook '{ANY_EXPR_HOOK_ID}' must run mypy "
            f"--disallow-any-expr over {', '.join(ANY_EXPR_PATHS)} with pass_filenames: false"
        )
    length = hooks.get(FILE_LENGTH_HOOK_ID)
    if length is None or length.pass_filenames or "check_file_length" not in length.entry:
        errors.append(
            f".pre-commit-config.yaml hook '{FILE_LENGTH_HOOK_ID}' must run "
            "check_file_length with pass_filenames: false"
        )


def strip_json_comments(text: str) -> str:
    """Return JSON-with-comments as plain JSON: comments and trailing commas removed."""
    out: list[str] = []
    index, in_string = 0, False
    while index < len(text):
        char, pair = text[index], text[index : index + 2]
        if in_string:
            out.append(text[index : index + 2] if char == "\\" else char)
            in_string = char != '"' or char == "\\"
            index += 2 if char == "\\" else 1
        elif pair in {"//", "/*"}:
            end = text.find("\n" if pair == "//" else "*/", index + 2)
            index = len(text) if end == -1 else end + (0 if pair == "//" else 2)
        else:
            in_string = char == '"'
            out.append(char)
            index += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def check_tsconfig(path: Path, errors: list[str]) -> None:
    """Append an error for each strict option the tsconfig lacks, and for skipLibCheck."""
    name = path.relative_to(ROOT)
    try:
        raw: object = json.loads(strip_json_comments(path.read_text(encoding="utf-8")))
    except ValueError as error:
        errors.append(f"{name}: cannot be read as a tsconfig: {error}")
        return
    config = as_table(raw)
    options = as_table(config.get("compilerOptions"))
    if not options:
        return  # a solution-style tsconfig that only references others
    errors.extend(
        f"{name}: compilerOptions.{key} must be true"
        for key in REQUIRED_TS_TRUE
        if options.get(key) is not True
    )
    if options.get("skipLibCheck") is True:
        errors.append(f"{name}: compilerOptions.skipLibCheck must not be true")


def check_frontend(errors: list[str]) -> None:
    """Strict TypeScript and the ESLint complexity ceiling, once the frontend exists."""
    frontend = ROOT / FRONTEND_DIR
    if not (frontend / "package.json").exists():
        return
    for path in sorted(frontend.glob("tsconfig*.json")):
        check_tsconfig(path, errors)
    for name in ESLINT_CONFIGS:
        path = frontend / name
        if not path.exists():
            continue
        code = "\n".join(
            line for line in path.read_text().splitlines() if not line.lstrip().startswith("//")
        )
        found = ESLINT_COMPLEXITY.search(code)
        if found is None or int(found.group(1)) > MAX_COMPLEXITY:
            errors.append(
                f'{FRONTEND_DIR}/{name} must set complexity: ["error", N] with N at most '
                f"{MAX_COMPLEXITY}"
            )


def main() -> int:
    """Run every check and return 1 with a report if any gate was loosened, otherwise 0."""
    errors: list[str] = []
    check_python(errors)
    check_hooks(errors)
    check_frontend(errors)
    if not errors:
        return 0
    sys.stderr.write("A quality gate has been loosened:\n")
    for error in errors:
        sys.stderr.write(f"  - {error}\n")
    sys.stderr.write("Fix the code, not the configuration. See CLAUDE.md, 'Quality gate'.\n")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
