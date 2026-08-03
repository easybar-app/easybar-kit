#!/bin/sh
set -eu

usage() {
  echo "Usage: $0 SVG_CONVERT SVG ICON_DIR SIZE [SIZE ...]" >&2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing $1. Install librsvg or set SVG_CONVERT=/path/to/rsvg-convert." >&2
    exit 1
  fi
}

require_file() {
  if [ ! -f "$1" ]; then
    echo "Missing $2: $1" >&2
    exit 1
  fi
}

if [ "$#" -lt 4 ]; then
  usage
  exit 2
fi

svg_convert=$1
svg=$2
icon_dir=$3
shift 3

require_command "$svg_convert"
require_file "$svg" "icon SVG"
mkdir -p "$icon_dir"

create_icon() {
  size=$1
  outfile=$2
  path="$icon_dir/$outfile"
  width=${size%x*}
  height=${size#*x}

  echo "create $path"
  "$svg_convert" \
    --width "$width" \
    --height "$height" \
    --keep-aspect-ratio \
    --output "$path" \
    "$svg"

  if [ ! -s "$path" ]; then
    echo "Could not create icon: $path" >&2
    exit 1
  fi
}

for size in "$@"; do
  create_icon "$size" "favicon-$size.png"
done

create_icon 180x180 apple-touch-icon.png
