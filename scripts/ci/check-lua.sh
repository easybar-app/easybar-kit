#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
widgets_dir="${repo_root}/widgets"
manifest_path="${widgets_dir}/install-manifest.csv"
lua_bin="${LUA:-lua}"

fail() {
  echo "Lua check failed: $*" >&2
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
    /*|../*|*/../*|*/..)
      fail "manifest line ${line_number} has an unsafe ${description}: ${path}"
      ;;
  esac
  [ -e "${widgets_dir}/${path}" ] \
    || fail "manifest ${description} does not exist: ${path}"
}

[ -d "${widgets_dir}" ] || fail "missing widgets directory: ${widgets_dir}"
[ -f "${manifest_path}" ] || fail "missing install manifest: ${manifest_path}"

manifest_entrypoints=()
manifest_names=()
manifest_dependencies=()
line_number=0
while IFS=';' read -r entrypoint dependencies extra || [ -n "${entrypoint}${dependencies}${extra}" ]; do
  line_number=$((line_number + 1))
  case "${entrypoint}" in
    ''|'#'*) continue ;;
  esac

  [ -z "${extra}" ] \
    || fail "manifest line ${line_number} must contain exactly two semicolon-separated fields"

  validate_relative_path "${entrypoint}" "entrypoint" "${line_number}"
  case "${entrypoint}" in
    *.lua) ;;
    *) fail "manifest line ${line_number} has a non-Lua entrypoint: ${entrypoint}" ;;
  esac

  if contains_value "${entrypoint}" "${manifest_entrypoints[@]}"; then
    fail "manifest contains a duplicate entrypoint: ${entrypoint}"
  fi

  name="${entrypoint%.lua}"
  if contains_value "${name}" "${manifest_names[@]}"; then
    fail "manifest contains a duplicate widget name: ${name}"
  fi

  row_dependencies=()
  if [ -n "${dependencies}" ]; then
    IFS=',' read -r -a parsed_dependencies <<<"${dependencies}"
    for dependency in "${parsed_dependencies[@]}"; do
      dependency="$(trim_whitespace "${dependency}")"
      validate_relative_path "${dependency}" "dependency" "${line_number}"

      if contains_value "${dependency}" "${row_dependencies[@]}"; then
        fail "manifest line ${line_number} contains a duplicate dependency: ${dependency}"
      fi

      row_dependencies+=("${dependency}")
      if ! contains_value "${dependency}" "${manifest_dependencies[@]}"; then
        manifest_dependencies+=("${dependency}")
      fi
    done
  fi

  manifest_entrypoints+=("${entrypoint}")
  manifest_names+=("${name}")
done <"${manifest_path}"

[ "${#manifest_entrypoints[@]}" -gt 0 ] || fail "manifest contains no widget entrypoints"

lua_files=()
while IFS= read -r file; do
  relative_path="${file#"${widgets_dir}/"}"
  lua_files+=("${relative_path}")

  if ! contains_value "${relative_path}" "${manifest_entrypoints[@]}" \
    && ! contains_value "${relative_path}" "${manifest_dependencies[@]}"; then
    fail "bundled Lua file is not declared by the install manifest: ${relative_path}"
  fi
done < <(find "${widgets_dir}" -type f -iname '*.lua' -print | LC_ALL=C sort)

[ "${#lua_files[@]}" -gt 0 ] || fail "widgets directory contains no Lua files"

for entrypoint in "${manifest_entrypoints[@]}"; do
  if grep -Eq '^[[:space:]]*require\("[^"]+"\)\(easybar\)[[:space:]]*$' "${widgets_dir}/${entrypoint}"; then
    fail "thin implementation wrapper remains: ${entrypoint}"
  fi
done

printf 'Widget Lua manifest validated (%d selectable widgets, %d Lua files).\n' \
  "${#manifest_entrypoints[@]}" \
  "${#lua_files[@]}"

command -v "${lua_bin}" >/dev/null 2>&1 \
  || fail "Lua 5.5 is required for syntax and bundled-widget checks: ${lua_bin}"

"${lua_bin}" -e 'assert(_VERSION == "Lua 5.5", "expected Lua 5.5, got " .. tostring(_VERSION))'

while IFS= read -r file; do
  LUA_CHECK_FILE="${file}" "${lua_bin}" -e \
    'local path = assert(os.getenv("LUA_CHECK_FILE")); assert(loadfile(path, "t", {}))'
done < <(find Sources widgets scripts -type f -iname '*.lua' -print | LC_ALL=C sort)

"${lua_bin}" scripts/ci/test-lua-runtime.lua "${repo_root}"
"${lua_bin}" scripts/ci/test-bundled-widgets.lua "${repo_root}" "${manifest_path}"
