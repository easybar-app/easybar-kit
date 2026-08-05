#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

lua_bin="${LUA:-lua}"

"${repo_root}/scripts/ci/check-widget-layout.sh" "${repo_root}/widgets" "${repo_root}/widgets/install-manifest.csv"

if ! command -v "${lua_bin}" >/dev/null 2>&1; then
  echo "Lua 5.4 is required for syntax and bundled-widget checks: ${lua_bin}" >&2
  exit 1
fi

"${lua_bin}" -e 'assert(_VERSION == "Lua 5.5", "expected Lua 5.5, got " .. tostring(_VERSION))'

if [ ! -f widgets/assets/github.svg ]; then
  echo "Bundled GitHub widget asset is missing: widgets/assets/github.svg" >&2
  exit 1
fi

while IFS= read -r file; do
  LUA_CHECK_FILE="${file}" "${lua_bin}" -e 'local path = assert(os.getenv("LUA_CHECK_FILE")); assert(loadfile(path, "t", {}))'
done < <(find Sources widgets scripts -type f -name '*.lua' -print | LC_ALL=C sort)

widget_files=()
while IFS= read -r file; do
  widget_files+=("${file}")
done < <(find widgets -maxdepth 1 -type f -name '*.lua' -print | LC_ALL=C sort)

"${lua_bin}" scripts/ci/smoke-bundled-widgets.lua "${repo_root}" "${widget_files[@]}"

inbox_widget_files=()
while IFS= read -r file; do
  inbox_widget_files+=("${file}")
done < <(find widgets -maxdepth 1 -type f -name '*-inbox.lua' -print | LC_ALL=C sort)

"${lua_bin}" scripts/ci/test-inbox-widget-activity.lua "${repo_root}" "${inbox_widget_files[@]}"

