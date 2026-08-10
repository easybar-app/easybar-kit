"""Helpers for stable generated artifact checks."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def normalize_markdown_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = [line.rstrip() for line in text.split("\n")]

    while lines and lines[-1] == "":
        lines.pop()

    if not lines:
        return ""

    return "\n".join(lines) + "\n"


def markdown_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []

    for path in paths:
        if not path.exists():
            continue

        if path.is_file():
            if path.suffix == ".md":
                files.append(path)
            continue

        if path.is_dir():
            files.extend(
                sorted(child for child in path.rglob("*.md") if child.is_file()))

    return sorted(set(files))


def normalize_markdown(paths: list[Path]) -> int:
    for path in markdown_files(paths):
        original = path.read_text(encoding="utf-8")
        normalized = normalize_markdown_text(original)

        if normalized != original:
            path.write_text(normalized, encoding="utf-8")

    return 0


def run_git(args: list[str], *, capture: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        check=False,
        encoding="utf-8",
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def git_diff_names(scopes: list[str]) -> list[str]:
    args = ["diff", "--name-only"]
    if scopes:
        args.extend(["--", *scopes])

    result = run_git(args)
    if result.returncode != 0:
        sys.stderr.write(result.stderr or "failed to read git diff\n")
        raise SystemExit(result.returncode)

    return [line for line in result.stdout.splitlines() if line]


def git_head_text(path: str) -> str | None:
    result = run_git(["show", f"HEAD:{path}"])
    if result.returncode != 0:
        return None

    return result.stdout


def worktree_text(path: str) -> str | None:
    file_path = Path(path)
    if not file_path.is_file():
        return None

    return file_path.read_text(encoding="utf-8")


def path_is_inside(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def is_normalized_markdown_path(path: str, roots: list[Path]) -> bool:
    candidate = Path(path)
    if candidate.suffix != ".md":
        return False

    for root in roots:
        if root.is_file() and candidate == root:
            return True

        if root.is_dir() and path_is_inside(candidate, root):
            return True

        if not root.exists():
            if root.suffix == ".md" and candidate == root:
                return True
            if root.suffix != ".md" and path_is_inside(candidate, root):
                return True

    return False


def markdown_diff_is_normalization_only(path: str) -> bool:
    head = git_head_text(path)
    current = worktree_text(path)

    if head is None or current is None:
        return False

    return normalize_markdown_text(head) == normalize_markdown_text(current)


def check_diff(normalized_markdown_roots: list[Path], scopes: list[str]) -> int:
    changed_paths = git_diff_names(scopes)
    if not changed_paths:
        return 0

    real_changes: list[str] = []
    ignored_changes: list[str] = []

    for changed_path in changed_paths:
        if is_normalized_markdown_path(changed_path, normalized_markdown_roots):
            if markdown_diff_is_normalization_only(changed_path):
                ignored_changes.append(changed_path)
                continue

        real_changes.append(changed_path)

    if not real_changes:
        if ignored_changes:
            print("Generated Markdown differs only by normalized whitespace:")
            for path in ignored_changes:
                print(path)
        return 0

    print("Generated artifacts are out of date:")
    for path in real_changes:
        print(path)
    print()
    print("Run 'make generate' and commit the result.")
    sys.stdout.flush()

    diff_args = ["diff", "--exit-code", "--", *real_changes]
    subprocess.run(["git", *diff_args], check=False)
    return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    normalize_parser = subparsers.add_parser(
        "normalize-markdown",
        help="Normalize generated Markdown files in place.",
    )
    normalize_parser.add_argument("paths", nargs="+")

    check_parser = subparsers.add_parser(
        "check-diff",
        help="Verify generated artifacts while ignoring normalized Markdown whitespace.",
    )
    check_parser.add_argument(
        "--normalized-markdown",
        nargs="+",
        default=[],
        metavar="PATH",
        help="Generated Markdown files or directories to compare after normalization.",
    )
    check_parser.add_argument(
        "--scope",
        action="append",
        default=[],
        metavar="PATH",
        help="Restrict git diff checks to one path. May be repeated.",
    )

    return parser


def main() -> int:
    args = build_parser().parse_args()

    if args.command == "normalize-markdown":
        return normalize_markdown([Path(path) for path in args.paths])

    if args.command == "check-diff":
        return check_diff(
            [Path(path) for path in args.normalized_markdown],
            args.scope,
        )

    raise AssertionError(f"unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
