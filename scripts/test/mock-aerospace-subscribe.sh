#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ] || [ "$1" != "subscribe" ] || [ "$2" != "--all" ]; then
  echo "unexpected arguments: $*" >&2
  exit 64
fi

printf '{"_event":"focused-workspace-changed"}\n'
