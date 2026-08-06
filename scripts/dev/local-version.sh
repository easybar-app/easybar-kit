#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF_USAGE'
Usage: scripts/dev/local-version.sh [--version-prefix PREFIX]

Print the version used by make install-local. The version contains the latest
release version reachable from HEAD, the current short Git commit, and a -dirty
suffix when the working tree contains tracked, staged, or untracked source changes.
EOF_USAGE
}

version_prefix="${VERSION_PREFIX:-v}"

while [ "$#" -gt 0 ]; do
  case "$1" in
  --version-prefix)
    if [ "$#" -lt 2 ]; then
      echo "Missing value for --version-prefix" >&2
      exit 2
    fi
    version_prefix="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    usage
    exit 2
    ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"
cd "$project_root"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Local version requires a Git working tree: $project_root" >&2
  exit 1
fi

head_commit="$(git rev-parse --verify HEAD)"
short_commit="$(git rev-parse --short=8 "$head_commit")"
latest_tag="$(
  git tag --merged "$head_commit" --list "${version_prefix}*" --sort=-v:refname |
    sed -n '1p'
)"

if [ -n "$latest_tag" ]; then
  base_version="${latest_tag#"$version_prefix"}"
else
  base_version="0.0.0"
fi

dirty=false
if ! git diff --quiet HEAD -- .; then
  dirty=true
fi
if [ -n "$(git ls-files --others --exclude-standard)" ]; then
  dirty=true
fi

version="${base_version}-dev.${short_commit}"
if [ "$dirty" = true ]; then
  version="${version}-dirty"
fi

printf '%s\n' "$version"
