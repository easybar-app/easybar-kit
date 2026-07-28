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

is_selected() {
  local candidate="$1"
  local selected

  if [ "${#selected_indices[@]}" -eq 0 ]; then
    return 1
  fi

  for selected in "${selected_indices[@]}"; do
    if [ "${selected}" = "${candidate}" ]; then
      return 0
    fi
  done

  return 1
}

add_selection() {
  local index="$1"

  if ! is_selected "${index}"; then
    selected_indices+=("${index}")
  fi
}

printf 'Install bundled EasyBar widgets into:\n  %s\n\n' "${destination_dir}"
printf 'Select items by number or name, separated by spaces.\n'
printf 'Press Return for the defaults, or enter "all" for everything.\n\n'

for index in "${!item_names[@]}"; do
  marker=" "

  if is_default "${item_names[${index}]}"; then
    marker="*"
  fi

  printf '  %2d) [%s] %s\n' \
    "$((index + 1))" \
    "${marker}" \
    "${item_labels[${index}]}"
done

printf '\n* selected by default\n'
printf '\nSelection: '

IFS= read -r selection
selection="${selection//,/ }"

if [ -z "${selection//[[:space:]]/}" ]; then
  for index in "${!item_names[@]}"; do
    if is_default "${item_names[${index}]}"; then
      add_selection "${index}"
    fi
  done
elif [ "${selection}" = "all" ]; then
  for index in "${!item_names[@]}"; do
    add_selection "${index}"
  done
else
  for token in ${selection}; do
    matched=false

    if [[ "${token}" =~ ^[0-9]+$ ]]; then
      number=$((10#${token}))

      if [ "${number}" -ge 1 ] &&
        [ "${number}" -le "${#item_names[@]}" ]; then
        add_selection "$((number - 1))"
        matched=true
      fi
    else
      normalized="${token%/}"
      normalized="${normalized%.lua}"

      for index in "${!item_names[@]}"; do
        if [ "${normalized}" = "${item_names[${index}]}" ]; then
          add_selection "${index}"
          matched=true
          break
        fi
      done
    fi

    if [ "${matched}" = false ]; then
      echo "Unknown selection: ${token}" >&2
      exit 2
    fi
  done
fi

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
