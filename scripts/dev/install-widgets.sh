#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF_USAGE'
Usage: scripts/dev/install-widgets.sh <source-dir> <destination-dir>
EOF_USAGE
}

if [ "$#" -ne 2 ]; then
  usage
  exit 2
fi

source_dir="$1"
destination_dir="$2"

if [ ! -d "${source_dir}" ]; then
  echo "Widget source directory does not exist: ${source_dir}" >&2
  exit 1
fi

if ! command -v fzf >/dev/null 2>&1; then
  echo "fzf is required to select widgets." >&2
  exit 1
fi

item_names=()
item_labels=()
item_sources=()
item_kinds=()
selected_indices=()

for path in "${source_dir}"/*.lua; do
  [ -f "${path}" ] || continue

  filename="$(basename "${path}")"

  item_names+=("${filename%.lua}")
  item_labels+=("${filename}")
  item_sources+=("${path}")
  item_kinds+=("file")
done

for directory in lib assets; do
  path="${source_dir}/${directory}"

  if [ -d "${path}" ]; then
    item_names+=("${directory}")
    item_labels+=("${directory}/")
    item_sources+=("${path}")
    item_kinds+=("directory")
  fi
done

if [ "${#item_names[@]}" -eq 0 ]; then
  echo "No bundled widgets or shared directories found in ${source_dir}" >&2
  exit 1
fi

default_names=(
  brew-inbox
  github-inbox
  gitlab-inbox
  inbox-demo
  tailscale
  lib
  assets
)

is_default() {
  local candidate="$1"
  local default_name

  for default_name in "${default_names[@]}"; do
    if [ "${candidate}" = "${default_name}" ]; then
      return 0
    fi
  done

  return 1
}

build_default_selection_binding() {
  local binding="first"
  local index
  local last_index="$((${#item_names[@]} - 1))"

  for index in "${!item_names[@]}"; do
    if is_default "${item_names[${index}]}"; then
      binding+="+toggle"
    fi

    if [ "${index}" -lt "${last_index}" ]; then
      binding+="+down"
    fi
  done

  printf '%s+first' "${binding}"
}

printf 'Install bundled EasyBar widgets into:\n  %s\n\n' "${destination_dir}"
printf 'Use Up/Down to move, Space to select or deselect, and Enter to install.\n'
printf 'The default widgets are preselected. Press Esc to cancel.\n\n'

default_selection_binding="$(build_default_selection_binding)"

if ! selection="$(
  for index in "${!item_names[@]}"; do
    printf '%d\t%2d) %s\n' \
      "${index}" \
      "$((index + 1))" \
      "${item_labels[${index}]}"
  done | fzf \
    --multi \
    --sync \
    --height=80% \
    --layout=reverse \
    --border \
    --no-sort \
    --delimiter=$'\t' \
    --with-nth=2.. \
    --marker='*' \
    --pointer='>' \
    --prompt='Widgets> ' \
    --header='Up/Down move | Space toggle | Enter confirm | Esc cancel' \
    --bind "start:${default_selection_binding}" \
    --bind 'space:toggle'
)"; then
  echo "Selection cancelled."
  exit 0
fi

while IFS=$'\t' read -r index _; do
  [ -n "${index}" ] || continue
  selected_indices+=("${index}")
done <<< "${selection}"

if [ "${#selected_indices[@]}" -eq 0 ]; then
  echo "Nothing selected." >&2
  exit 2
fi

mkdir -p "${destination_dir}"

printf '\nCopying:\n'

for index in "${selected_indices[@]}"; do
  name="${item_names[${index}]}"
  label="${item_labels[${index}]}"
  source="${item_sources[${index}]}"
  kind="${item_kinds[${index}]}"

  printf '  %s\n' "${label}"

  if [ "${kind}" = "file" ]; then
    cp "${source}" "${destination_dir}/${label}"
  else
    mkdir -p "${destination_dir}/${name}"
    cp -R "${source}/." "${destination_dir}/${name}/"
  fi
done

printf '\nInstalled selected widgets into %s\n' "${destination_dir}"
printf 'Restart the Lua runtime with: easybar runtime restart\n'
