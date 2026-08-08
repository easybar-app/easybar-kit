#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
examples_dir="${repo_root}/examples"
manifest_path="${examples_dir}/install-manifest.csv"

fail() {
  echo "Example layout check failed: $*" >&2
  exit 1
}

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

validate_relative_path() {
  local path="$1"
  local description="$2"
  local line_number="$3"

  [ -n "${path}" ] || fail "manifest line ${line_number} has an empty ${description}"
  case "${path}" in
  /* | ../* | */../* | */..)
    fail "manifest line ${line_number} has an unsafe ${description}: ${path}"
    ;;
  esac

  [ -e "${examples_dir}/${path}" ] ||
    fail "manifest ${description} does not exist: ${path}"
}

[ -d "${examples_dir}" ] || fail "missing examples directory: ${examples_dir}"
[ -f "${manifest_path}" ] || fail "missing install manifest: ${manifest_path}"

entrypoints=()
dependencies=()
line_number=0

while IFS=';' read -r entrypoint dependency_list extra || [ -n "${entrypoint}${dependency_list}${extra}" ]; do
  line_number=$((line_number + 1))
  case "${entrypoint}" in
  '' | '#'*) continue ;;
  esac

  [ -z "${extra}" ] ||
    fail "manifest line ${line_number} must contain exactly two semicolon-separated fields"

  validate_relative_path "${entrypoint}" "entrypoint" "${line_number}"
  case "${entrypoint}" in
  *.lua) ;;
  *) fail "manifest line ${line_number} has a non-Lua entrypoint: ${entrypoint}" ;;
  esac

  if contains_value "${entrypoint}" "${entrypoints[@]-}"; then
    fail "manifest contains a duplicate entrypoint: ${entrypoint}"
  fi
  entrypoints+=("${entrypoint}")

  row_dependencies=()
  if [ -n "${dependency_list}" ]; then
    IFS=',' read -r -a parsed_dependencies <<<"${dependency_list}"
    for dependency in "${parsed_dependencies[@]}"; do
      dependency="$(trim_whitespace "${dependency}")"
      validate_relative_path "${dependency}" "dependency" "${line_number}"

      if contains_value "${dependency}" "${row_dependencies[@]-}"; then
        fail "manifest line ${line_number} contains a duplicate dependency: ${dependency}"
      fi

      row_dependencies+=("${dependency}")
      if ! contains_value "${dependency}" "${dependencies[@]-}"; then
        dependencies+=("${dependency}")
      fi
    done
  fi
done <"${manifest_path}"

[ "${#entrypoints[@]}" -gt 0 ] || fail "manifest contains no widget entrypoints"

lua_file_count=0
while IFS= read -r file; do
  relative_path="${file#"${examples_dir}/"}"
  lua_file_count=$((lua_file_count + 1))

  if ! contains_value "${relative_path}" "${entrypoints[@]-}" &&
    ! contains_value "${relative_path}" "${dependencies[@]-}"; then
    fail "example Lua file is not declared by the install manifest: ${relative_path}"
  fi
done < <(find "${examples_dir}" -type f -iname '*.lua' -print | LC_ALL=C sort)

[ "${lua_file_count}" -gt 0 ] || fail "examples directory contains no Lua files"

for entrypoint in "${entrypoints[@]}"; do
  if grep -Eq '^[[:space:]]*require\("[^"]+"\)\(easybar\)[[:space:]]*$' "${examples_dir}/${entrypoint}"; then
    fail "thin implementation wrapper remains: ${entrypoint}"
  fi
done

printf 'Example layout validated (%d selectable widgets, %d Lua files).\n' \
  "${#entrypoints[@]}" \
  "${lua_file_count}"
