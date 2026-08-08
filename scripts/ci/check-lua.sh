#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
lua_bin="${LUA:-lua}"

cd "${repo_root}"

fail() {
  echo "Lua check failed: $*" >&2
  exit 1
}

scripts/ci/check-example-layout.sh

command -v "${lua_bin}" >/dev/null 2>&1 ||
  fail "Lua 5.5 is required: ${lua_bin}"

"${lua_bin}" -e 'assert(_VERSION == "Lua 5.5", "expected Lua 5.5, got " .. tostring(_VERSION))'

while IFS= read -r file; do
  LUA_CHECK_FILE="${file}" "${lua_bin}" -e \
    'local path = assert(os.getenv("LUA_CHECK_FILE")); assert(loadfile(path, "t", {}))'
done < <(find Sources examples scripts Tests -type f -iname '*.lua' -print | LC_ALL=C sort)

test_count=0
while IFS= read -r test_file; do
  test_count=$((test_count + 1))
  "${lua_bin}" "${test_file}" "${repo_root}"
done < <(find Tests/lua -type f -name 'test.lua' -print | LC_ALL=C sort)

[ "${test_count}" -gt 0 ] || fail "no Lua regression tests were discovered"
printf 'Lua regression tests passed (%d files).\n' "${test_count}"
