#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/build/clean-dist-dir.sh [--check] <dist-dir>" >&2
}

check_only=false
if [ "${1:-}" = "--check" ]; then
  check_only=true
  shift
fi

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  usage
  exit 2
fi

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
dist_dir="$1"
if [[ "$dist_dir" = /* ]]; then
  candidate="$dist_dir"
else
  candidate="$project_root/$dist_dir"
fi

resolved_dir="$(
  python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$candidate"
)"
resolved_parent="$(dirname "$resolved_dir")"
resolved_name="$(basename "$resolved_dir")"

case "$resolved_name" in
dist | dist-* | dist_*) ;;
*)
  echo "Refusing to clean unsafe distribution directory: $dist_dir" >&2
  echo "Use a repository-root directory named dist, dist-*, or dist_*." >&2
  exit 2
  ;;
esac

if [ "$resolved_parent" != "$project_root" ]; then
  echo "Refusing to clean distribution directory outside the repository root: $dist_dir" >&2
  exit 2
fi

if [ "$check_only" = true ]; then
  exit 0
fi

rm -rf "$resolved_dir"
