#!/usr/bin/env python3
"""Verify that checked-in generated artifacts match their generators."""

from __future__ import annotations

import argparse
import subprocess
import sys


def git_diff_names(scopes: list[str]) -> list[str]:
    """Return changed paths for the requested Git scopes."""
    args = ["git", "diff", "--name-only", "HEAD"]
    if scopes:
        args.extend(["--", *scopes])

    result = subprocess.run(args, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr or "failed to read generated artifact diff\n")
        raise SystemExit(result.returncode)

    return [line for line in result.stdout.splitlines() if line]


def check_diff(scopes: list[str]) -> int:
    """Report generated files changed by regeneration."""
    changed_paths = git_diff_names(scopes)
    if not changed_paths:
        return 0

    print("Generated artifacts are out of date:")
    for path in changed_paths:
        print(path)
    print("\nRun 'make generate' and commit the result.")
    sys.stdout.flush()

    subprocess.run(
        ["git", "diff", "--exit-code", "HEAD", "--", *changed_paths],
        check=False,
    )
    return 1


def build_parser() -> argparse.ArgumentParser:
    """Build the command-line argument parser."""
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    check_parser = subparsers.add_parser(
        "check-diff",
        help="Verify that generated artifacts have no changes from HEAD.",
    )
    check_parser.add_argument(
        "--scope",
        action="append",
        default=[],
        metavar="PATH",
        help="Restrict the check to one generated path. May be repeated.",
    )

    return parser


def main() -> int:
    """Run the command-line entry point."""
    args = build_parser().parse_args()
    if args.command == "check-diff":
        return check_diff(args.scope)
    raise AssertionError(f"unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
