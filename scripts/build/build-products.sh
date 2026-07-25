#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <debug|release> <arm64|x86_64|universal> [--version <version>] <product=output> [...]" >&2
}

if [ "$#" -lt 3 ]; then
  usage
  exit 2
fi

configuration=$1
arch=$2
shift 2
version="dev"

if [ "${1:-}" = "--version" ]; then
  if [ "$#" -lt 3 ]; then
    usage
    exit 2
  fi
  version=$2
  shift 2
fi

case "$configuration" in
debug | release) ;;
*)
  echo "Unsupported configuration '$configuration'. Use debug or release." >&2
  exit 2
  ;;
esac

case "$arch" in
arm64 | x86_64 | universal) ;;
*)
  echo "Unsupported architecture '$arch'. Use arm64, x86_64, or universal." >&2
  exit 2
  ;;
esac

if [ -z "$version" ]; then
  echo "Build version must not be empty." >&2
  exit 2
fi

products=()
outputs=()
for pair in "$@"; do
  case "$pair" in
  *=*) ;;
  *)
    echo "Invalid product mapping '$pair'. Expected <product=output>." >&2
    exit 2
    ;;
  esac

  product=${pair%%=*}
  output=${pair#*=}
  if [ -z "$product" ] || [ -z "$output" ]; then
    echo "Invalid product mapping '$pair'. Expected non-empty product and output." >&2
    exit 2
  fi

  products+=("$product")
  outputs+=("$output")
  mkdir -p "$(dirname "$output")"
done

build_product_path() {
  local built_arch=$1
  local product=$2

  printf '.build/%s-apple-macosx/%s/%s\n' "$built_arch" "$configuration" "$product"
}

require_built_product() {
  local path=$1
  local product=$2

  if [ ! -f "$path" ]; then
    echo "SwiftPM did not produce product '$product' at: $path" >&2
    exit 1
  fi
}

write_build_version() {
  local version_file=".build/easybar-build-version"
  local temporary_file="${version_file}.tmp.$$"

  mkdir -p "$(dirname "$version_file")"
  printf '%s\n' "$version" >"$temporary_file"

  if [ -f "$version_file" ] && cmp -s "$temporary_file" "$version_file"; then
    rm -f "$temporary_file"
  else
    mv -f "$temporary_file" "$version_file"
  fi
}

build_product() {
  local build_arch=$1
  local product=$2

  swift build -c "$configuration" --arch "$build_arch" --product "$product"
}

build_arch() {
  local build_arch=$1
  local product

  for product in "${products[@]}"; do
    build_product "$build_arch" "$product"
  done
}

copy_arch_outputs() {
  local built_arch=$1
  local index=0

  while [ "$index" -lt "${#products[@]}" ]; do
    local product=${products[$index]}
    local source_path
    source_path=$(build_product_path "$built_arch" "$product")
    require_built_product "$source_path" "$product"
    cp "$source_path" "${outputs[$index]}"
    index=$((index + 1))
  done
}

lipo_universal_outputs() {
  local index=0

  if ! command -v lipo >/dev/null 2>&1; then
    echo "Missing lipo. Universal builds must run with Xcode command line tools available." >&2
    exit 1
  fi

  while [ "$index" -lt "${#products[@]}" ]; do
    local product=${products[$index]}
    local arm64_path
    local x86_64_path
    arm64_path=$(build_product_path arm64 "$product")
    x86_64_path=$(build_product_path x86_64 "$product")

    require_built_product "$arm64_path" "$product"
    require_built_product "$x86_64_path" "$product"

    lipo -create "$arm64_path" "$x86_64_path" -output "${outputs[$index]}"
    require_built_product "${outputs[$index]}" "$product"
    index=$((index + 1))
  done
}

write_build_version

if [ "$arch" = "universal" ]; then
  build_arch arm64
  build_arch x86_64
  lipo_universal_outputs
else
  build_arch "$arch"
  copy_arch_outputs "$arch"
fi
