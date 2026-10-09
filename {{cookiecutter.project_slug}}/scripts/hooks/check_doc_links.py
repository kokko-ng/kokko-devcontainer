"""Fail if a relative link or image in a tracked Markdown file points at nothing.

A link that has rotted sends a reader to a 404 and tells them the documentation is not
kept up. This check reads every tracked Markdown file (``git ls-files '*.md'``), finds the
inline links, images, and reference definitions outside code, and verifies the ones that
stay inside the repository:

- the target file or directory must be tracked, so a path that exists only in a local
  working tree is reported rather than passing here and failing in CI;
- a ``#anchor`` into a Markdown file must match a heading slug, using GitHub's slug rules
  (duplicates get ``-1``, ``-2``), or an explicit ``<a name=...>`` or ``id=...`` anchor;
- a pure in-page ``#anchor`` is verified against the same file's headings.

Links with a scheme (``https:``, ``mailto:``) are not checked: they need the network.
Anything under ``node_modules`` is not read. Headings are ATX (``#``)
headings. The fix for a finding is to correct the link, never this check.
"""

from __future__ import annotations

import posixpath
import re
import subprocess
import sys
from pathlib import Path
from typing import TYPE_CHECKING, NamedTuple
from urllib.parse import unquote

if TYPE_CHECKING:
    from collections.abc import Callable

ROOT = Path(__file__).resolve().parents[2]

SKIPPED_PARTS = ("node_modules",)
LINK_OPEN = re.compile(r"\]\(")
REFERENCE_DEFINITION = re.compile(r"^ {0,3}\[[^\]]+\]:\s*<?([^\s>]+)")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
INLINE_CODE = re.compile(r"(`+)(?:(?!\1).)+?\1")
HEADING = re.compile(r"^ {0,3}#{1,6}[ \t]+(.*?)[ \t]*#*[ \t]*$")
HEADING_LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")
HTML_TAG = re.compile(r"<[^>]+>")
NOT_IN_SLUG = re.compile(r"[^\w\- ]")
EXPLICIT_ANCHOR = re.compile(r"""<[a-zA-Z][^>]*\b(?:name|id)\s*=\s*["']([^"']+)["']""")
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.\-]*:")


class Link(NamedTuple):
    """A link found in a file: the line it is on (1-based) and its raw target."""

    line: int
    target: str


class Document(NamedTuple):
    """A Markdown file reduced to what link checking needs."""

    links: list[Link]
    anchors: set[str]


def is_skipped(path: str) -> bool:
    """Return True for a path this check does not read: installed dependencies."""
    return any(part in SKIPPED_PARTS for part in path.split("/"))


def fence_char(line: str) -> str | None:
    """Return the fence character (backtick or tilde) if the line opens or closes a fence."""
    return line.lstrip()[0] if FENCE.match(line) else None


def mask_fences(lines: list[str]) -> list[str]:
    """Return the lines with the contents of fenced code blocks blanked, line numbers kept."""
    masked: list[str] = []
    fence: str | None = None
    for line in lines:
        char = fence_char(line)
        if fence is None:
            fence = char
            masked.append("" if char else line)
        else:
            if char == fence:
                fence = None
            masked.append("")
    return masked


def link_target(line: str, start: int) -> str | None:
    """Return the destination of the link whose ``(`` is just before ``start``, if well formed."""
    index = start
    while index < len(line) and line[index] in " \t":
        index += 1
    if index < len(line) and line[index] == "<":
        end = line.find(">", index)
        return line[index + 1 : end] if end != -1 else None
    depth = 0
    begin = index
    while index < len(line):
        char = line[index]
        if char in " \t":
            break
        if char == "(":
            depth += 1
        elif char == ")":
            if depth == 0:
                break
            depth -= 1
        index += 1
    return line[begin:index]


def _blank(found: re.Match[str]) -> str:
    """Return spaces as long as the match, so a code span keeps its width but holds no link."""
    return " " * len(found.group(0))


def links_in_line(number: int, line: str) -> list[Link]:
    """Return the inline links and images of one line, ignoring inline code spans."""
    text = INLINE_CODE.sub(_blank, line)
    links = [Link(number, target) for target in _inline_targets(text)]
    definition = REFERENCE_DEFINITION.match(text)
    if definition:
        links.append(Link(number, str(definition.group(1))))
    return links


def _inline_targets(text: str) -> list[str]:
    """Return the non-empty destinations of every ``](...)`` in the text."""
    targets: list[str] = []
    for opening in LINK_OPEN.finditer(text):
        target = link_target(text, opening.end())
        if target:
            targets.append(target)
    return targets


def heading_slug(heading: str) -> str:
    """Return the GitHub anchor for a heading's text, before duplicate numbering."""
    text = HEADING_LINK.sub(r"\1", heading)
    text = HTML_TAG.sub("", text).lower()
    return NOT_IN_SLUG.sub("", text).strip().replace(" ", "-")


def heading_anchors(lines: list[str]) -> set[str]:
    """Return every heading anchor of the file, numbering duplicates as GitHub does."""
    seen: dict[str, int] = {}
    anchors: set[str] = set()
    for line in lines:
        found = HEADING.match(line)
        if not found:
            continue
        slug = heading_slug(found.group(1))
        count = seen.get(slug, 0)
        seen[slug] = count + 1
        anchors.add(slug if count == 0 else f"{slug}-{count}")
    return anchors


def parse_document(text: str) -> Document:
    """Return the links and the anchors (headings and explicit) of a Markdown file."""
    lines = mask_fences(text.splitlines())
    links: list[Link] = []
    for number, line in enumerate(lines, start=1):
        links.extend(links_in_line(number, line))
    explicit = {str(m.group(1)).lower() for line in lines for m in EXPLICIT_ANCHOR.finditer(line)}
    return Document(links, heading_anchors(lines) | explicit)


def tracked_markdown(root: Path) -> tuple[list[str], set[str]]:
    """Return the tracked Markdown paths to check, and every tracked path, as POSIX paths."""
    # Fixed argument list, no shell, no external input.
    result = subprocess.run(
        ["git", "ls-files", "-z"],  # noqa: S607 -- git is resolved from PATH, as in the other hooks
        check=True,
        capture_output=True,
        text=True,
        cwd=root,
    )
    tracked = [path for path in result.stdout.split("\0") if path]
    markdown = [path for path in tracked if path.endswith(".md") and not is_skipped(path)]
    return markdown, set(tracked)


def tracked_targets(tracked: set[str]) -> set[str]:
    """Return every tracked file and every directory that holds one, as POSIX paths."""
    targets = set(tracked)
    for path in tracked:
        parent = posixpath.dirname(path)
        while parent and parent not in targets:
            targets.add(parent)
            parent = posixpath.dirname(parent)
    return targets


def resolve(source: str, path: str) -> str | None:
    """Return the repository-relative target of a link in ``source``, or None if it escapes."""
    base = "" if path.startswith("/") else posixpath.dirname(source)
    joined = posixpath.normpath(posixpath.join(base, path.lstrip("/")))
    if joined == ".." or joined.startswith("../"):
        return None
    return "" if joined == "." else joined


class Checker:
    """Checks the links of tracked Markdown files against the tracked tree."""

    def __init__(self, tracked: set[str], read: Callable[[str], str]) -> None:
        """Hold the tracked paths and a reader that returns a tracked file's text."""
        self._targets = tracked_targets(tracked)
        self._read = read
        self._documents: dict[str, Document] = {}

    def document(self, path: str) -> Document:
        """Return the parsed file, reading and parsing it once."""
        if path not in self._documents:
            self._documents[path] = parse_document(self._read(path))
        return self._documents[path]

    def problem(self, source: str, target: str) -> str | None:
        """Return why a link in ``source`` is broken, or None if it holds or is not checked."""
        if SCHEME.match(target):
            return None
        raw_path, _, raw_anchor = target.partition("#")
        path = unquote(raw_path.partition("?")[0])
        destination = source if not path else resolve(source, path)
        if destination is None or (destination and destination not in self._targets):
            return f"'{target}' does not exist"
        return self._anchor_problem(target, destination, unquote(raw_anchor).lower())

    def _anchor_problem(self, target: str, destination: str, anchor: str) -> str | None:
        """Return why the anchor is missing from a Markdown destination, or None if it holds."""
        if not anchor or not destination.endswith(".md"):
            return None
        if anchor in self.document(destination).anchors:
            return None
        return f"'{target}' has no heading or anchor '{anchor}' in {destination}"

    def check_file(self, source: str) -> list[str]:
        """Return one message for each broken link of the file."""
        errors: list[str] = []
        for link in self.document(source).links:
            reason = self.problem(source, link.target)
            if reason:
                errors.append(f"{source}:{link.line}: {reason}")
        return errors


def check_documents(
    markdown: list[str], tracked: set[str], read: Callable[[str], str]
) -> list[str]:
    """Return one message for every broken link in the Markdown files."""
    checker = Checker(tracked, read)
    return [error for source in markdown for error in checker.check_file(source)]


def main() -> int:
    """Return 1 with a report if any tracked Markdown file has a broken relative link."""
    markdown, tracked = tracked_markdown(ROOT)
    present = [path for path in markdown if (ROOT / path).is_file()]
    errors = check_documents(present, tracked, lambda path: (ROOT / path).read_text())
    if not errors:
        return 0
    sys.stderr.write("Broken links in Markdown files:\n")
    for error in errors:
        sys.stderr.write(f"  - {error}\n")
    sys.stderr.write("Fix the link (target or anchor), not the check.\n")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
