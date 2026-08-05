#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF_USAGE'
Usage: scripts/dev/install-widgets.sh <source-dir> <destination-dir> <manifest>
EOF_USAGE
}

if [ "$#" -ne 3 ]; then
  usage
  exit 2
fi

source_dir="$1"
destination_dir="$2"
manifest_path="$3"

if [ ! -d "${source_dir}" ]; then
  echo "Widget source directory does not exist: ${source_dir}" >&2
  exit 1
fi

if [ ! -f "${manifest_path}" ]; then
  echo "Widget install manifest does not exist: ${manifest_path}" >&2
  exit 1
fi

if ! command -v fzf >/dev/null 2>&1; then
  echo "fzf is required to select widgets." >&2
  exit 1
fi

item_names=()
item_labels=()
item_entrypoints=()
selected_indices=()
dependency_paths=()

contains_value() {
  local candidate="$1"
  shift
  local value

  for value in "$@"; do
    if [ "${value}" = "${candidate}" ]; then
      return 0
    fi
  done

  return 1
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

while IFS=';' read -r entrypoint _ extra || [ -n "${entrypoint}${extra}" ]; do
  case "${entrypoint}" in
    ''|'#'*) continue ;;
  esac

  if [ -n "${extra}" ]; then
    echo "Invalid manifest row for ${entrypoint}: expected exactly two semicolon-separated fields" >&2
    exit 1
  fi

  if contains_value "${entrypoint}" "${item_entrypoints[@]}"; then
    echo "Duplicate widget entrypoint in manifest: ${entrypoint}" >&2
    exit 1
  fi

  case "${entrypoint}" in
    *.lua)
      name="${entrypoint%.lua}"
      label="${entrypoint}"
      ;;
    *)
      echo "Invalid widget entrypoint in manifest: ${entrypoint}" >&2
      exit 1
      ;;
  esac

  item_names+=("${name}")
  item_labels+=("${label}")
  item_entrypoints+=("${entrypoint}")
done <"${manifest_path}"

if [ "${#item_names[@]}" -eq 0 ]; then
  echo "No bundled widget entrypoints found in ${manifest_path}" >&2
  exit 1
fi

default_names=(
  inbox/brew/widget
  inbox/github/widget
  inbox/gitlab/widget
  inbox/demo/widget
  tailscale/widget
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

append_dependency() {
  local relative_path="$1"

  if [ -z "${relative_path}" ]; then
    return
  fi

  case "${relative_path}" in
    /*|../*|*/../*|*/..)
      echo "Invalid dependency path in manifest: ${relative_path}" >&2
      exit 1
      ;;
  esac

  if ! contains_value "${relative_path}" "${dependency_paths[@]}"; then
    dependency_paths+=("${relative_path}")
  fi
}

append_dependencies() {
  local dependencies="$1"
  local dependency
  local -a parsed_dependencies=()

  [ -n "${dependencies}" ] || return 0

  IFS=',' read -r -a parsed_dependencies <<<"${dependencies}"
  for dependency in "${parsed_dependencies[@]}"; do
    dependency="$(trim_whitespace "${dependency}")"
    if [ -z "${dependency}" ]; then
      echo "Invalid empty dependency in manifest" >&2
      exit 1
    fi
    append_dependency "${dependency}"
  done
}

collect_dependencies() {
  local selected_entrypoint="$1"
  local entrypoint
  local dependencies
  local extra

  while IFS=';' read -r entrypoint dependencies extra || [ -n "${entrypoint}${dependencies}${extra}" ]; do
    case "${entrypoint}" in
      ''|'#'*) continue ;;
    esac

    if [ -n "${extra}" ]; then
      echo "Invalid manifest row for ${entrypoint}: expected exactly two semicolon-separated fields" >&2
      exit 1
    fi

    if [ "${entrypoint}" = "${selected_entrypoint}" ]; then
      append_dependencies "${dependencies}"
      return
    fi
  done <"${manifest_path}"

  echo "Selected widget is missing from manifest: ${selected_entrypoint}" >&2
  exit 1
}

copy_relative_path() {
  local relative_path="$1"
  local source="${source_dir}/${relative_path}"
  local destination="${destination_dir}/${relative_path}"

  if [ ! -e "${source}" ]; then
    echo "Bundled widget dependency does not exist: ${relative_path}" >&2
    exit 1
  fi

  printf '  %s\n' "${relative_path}"

  if [ -d "${source}" ]; then
    mkdir -p "${destination}"
    cp -R "${source}/." "${destination}/"
  else
    mkdir -p "$(dirname "${destination}")"
    cp "${source}" "${destination}"
  fi
}

printf 'Install bundled EasyBar widgets into:\n  %s\n\n' "${destination_dir}"
printf 'Use Up/Down to move, Space to select or deselect, and Enter to install.\n'
printf 'Dependencies are copied automatically from the widget manifest.\n'
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
done <<<"${selection}"

if [ "${#selected_indices[@]}" -eq 0 ]; then
  echo "Nothing selected." >&2
  exit 2
fi

mkdir -p "${destination_dir}"

printf '\nCopying widget entrypoints:\n'

for index in "${selected_indices[@]}"; do
  entrypoint="${item_entrypoints[${index}]}"

  copy_relative_path "${entrypoint}"
  collect_dependencies "${entrypoint}"
done

if [ -f "${source_dir}/.luarc.json" ]; then
  append_dependency ".luarc.json"
fi

if [ "${#dependency_paths[@]}" -gt 0 ]; then
  printf '\nCopying dependencies:\n'
  for dependency in "${dependency_paths[@]}"; do
    copy_relative_path "${dependency}"
  done
fi

printf '\nInstalled selected widgets and dependencies into %s\n' "${destination_dir}"
printf 'Restart the Lua runtime with: easybar runtime restart\n'
