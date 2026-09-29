#!/usr/bin/env python3
"""Require one-line documentation for Swift declarations and stored data."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


DECLARATION = re.compile(
    r"^(?P<indent>\s*)"
    r"(?:(?:public|internal|private|fileprivate|package|open|static|class|mutating|"
    r"nonmutating|override|convenience|required|final|nonisolated|distributed)\s+)*"
    r"(?P<kind>func|init\??|deinit|subscript|struct|class|actor|enum|protocol)\b"
)
FIELD = re.compile(
    r"^(?P<indent>\s*)"
    r"(?:(?:public|internal|private|fileprivate|package|static|class|lazy|weak|unowned|"
    r"private\(set\)|public\(set\)|internal\(set\))\s+)*"
    r"(?:let|var)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
)
TYPE_KINDS = {"struct", "class", "actor", "enum", "protocol"}


@dataclass(frozen=True)
class TypeScope:
    """Tracks the indentation and kind of one enclosing Swift type."""

    indentation: int
    kind: str


def is_documented(lines: list[str], line_index: int) -> bool:
    """Return whether a declaration has an adjacent one-line documentation comment."""
    previous = line_index - 1
    while previous >= 0 and (not lines[previous].strip() or lines[previous].lstrip().startswith("@")):
        previous -= 1
    return previous >= 0 and lines[previous].lstrip().startswith("///")


def undocumented_lines(path: Path) -> list[tuple[int, str]]:
    """Return undocumented declaration and struct-field lines in one Swift source file."""
    lines = path.read_text(encoding="utf-8").splitlines()
    problems: list[tuple[int, str]] = []
    scopes: list[TypeScope] = []
    in_multiline_string = False

    for index, line in enumerate(lines):
        delimiter_count = line.count('"""')
        if in_multiline_string or delimiter_count:
            if delimiter_count % 2 == 1:
                in_multiline_string = not in_multiline_string
            continue

        indentation = len(line) - len(line.lstrip())
        if line.strip() == "}":
            while scopes and scopes[-1].indentation >= indentation:
                scopes.pop()

        declaration = DECLARATION.match(line)
        if declaration:
            if not is_documented(lines, index):
                problems.append((index + 1, line.strip()))

            kind = declaration.group("kind").rstrip("?")
            if kind in TYPE_KINDS:
                while scopes and scopes[-1].indentation >= indentation:
                    scopes.pop()
                scopes.append(TypeScope(indentation=indentation, kind=kind))
            continue

        field = FIELD.match(line)
        if (
            field
            and scopes
            and scopes[-1].kind == "struct"
            and indentation == scopes[-1].indentation + 2
            and not is_documented(lines, index)
        ):
            problems.append((index + 1, line.strip()))

    return problems


def main() -> int:
    """Check every production Swift source and print actionable failures."""
    repository = Path(__file__).resolve().parents[2]
    failures: list[str] = []
    for path in sorted((repository / "Sources").rglob("*.swift")):
        for line, declaration in undocumented_lines(path):
            failures.append(f"{path.relative_to(repository)}:{line}: {declaration}")

    if failures:
        print("Swift source documentation check failed:", file=sys.stderr)
        print("\n".join(failures), file=sys.stderr)
        return 1

    print("Swift source documentation check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
