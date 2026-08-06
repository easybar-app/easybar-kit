#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

tap_dir="${tmp_dir}/homebrew-tap"
version="9.8.7"
tag="v${version}"
sha="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
calendar_agent_sha="1123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
network_agent_sha="2123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

mkdir -p "${tap_dir}/Formula"
git -C "${tap_dir}" init -q
touch "${tap_dir}/Formula/easybar.rb" \
  "${tap_dir}/Formula/easybar-calendar-agent.rb" \
  "${tap_dir}/Formula/easybar-network-agent.rb"
git -C "${tap_dir}" add Formula
git -C "${tap_dir}" -c user.name=test -c user.email=test@example.com commit -qm fixture

"${repo_root}/scripts/release/update-homebrew-cask.sh" \
  --tap-dir "${tap_dir}" \
  --repository gi8lino/easybar \
  --tag "${tag}" \
  --version "${version}" \
  --sha "${sha}" \
  --calendar-agent-sha "${calendar_agent_sha}" \
  --network-agent-sha "${network_agent_sha}"

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq "${expected}" "${file}"; then
    echo "Expected ${file} to contain: ${expected}" >&2
    cat "${file}" >&2
    exit 1
  fi
}

easybar_cask="${tap_dir}/Casks/easybar.rb"
test -s "${easybar_cask}"
assert_contains "${easybar_cask}" 'cask "easybar" do'
assert_contains "${easybar_cask}" "url \"https://github.com/gi8lino/easybar/releases/download/${tag}/EasyBar-${version}.zip\""
assert_contains "${easybar_cask}" "sha256 \"${sha}\""
assert_contains "${easybar_cask}" "version \"${version}\""
assert_contains "${easybar_cask}" '"easybar-calendar-agent",'
assert_contains "${easybar_cask}" '"easybar-network-agent",'
assert_contains "${easybar_cask}" 'depends_on macos: :sonoma'
assert_contains "${easybar_cask}" 'system "xattr", "-d", "com.apple.quarantine", "#{staged_path}/easybar"'
assert_contains "${easybar_cask}" 'system "xattr", "-dr", "com.apple.quarantine", "#{appdir}/EasyBar.app"'
assert_contains "${easybar_cask}" '"services", "restart", "easybar-calendar-agent"'
assert_contains "${easybar_cask}" '"services", "restart", "easybar-network-agent"'
assert_contains "${easybar_cask}" '"services", "stop", "easybar-calendar-agent"'
assert_contains "${easybar_cask}" '"services", "stop", "easybar-network-agent"'
assert_contains "${easybar_cask}" 'app "EasyBar.app"'
assert_contains "${easybar_cask}" 'binary "easybar"'

test ! -e "${tap_dir}/Formula/easybar.rb"

calendar_formula="${tap_dir}/Formula/easybar-calendar-agent.rb"
network_formula="${tap_dir}/Formula/easybar-network-agent.rb"
test -s "${calendar_formula}"
test -s "${network_formula}"
assert_contains "${calendar_formula}" 'class EasybarCalendarAgent < Formula'
assert_contains "${calendar_formula}" "url \"https://github.com/gi8lino/easybar/releases/download/${tag}/EasyBarCalendarAgent-${version}.zip\""
assert_contains "${calendar_formula}" "sha256 \"${calendar_agent_sha}\""
assert_contains "${calendar_formula}" 'libexec.install "EasyBarCalendarAgent.app"'
assert_contains "${calendar_formula}" 'keep_alive successful_exit: false'
assert_contains "${calendar_formula}" 'process_type :interactive'
assert_contains "${network_formula}" 'class EasybarNetworkAgent < Formula'
assert_contains "${network_formula}" "url \"https://github.com/gi8lino/easybar/releases/download/${tag}/EasyBarNetworkAgent-${version}.zip\""
assert_contains "${network_formula}" "sha256 \"${network_agent_sha}\""
assert_contains "${network_formula}" 'libexec.install "EasyBarNetworkAgent.app"'
assert_contains "${network_formula}" 'keep_alive successful_exit: false'
assert_contains "${network_formula}" 'process_type :interactive'

ruby -c "${easybar_cask}" >/dev/null
ruby -c "${calendar_formula}" >/dev/null
ruby -c "${network_formula}" >/dev/null

"${repo_root}/scripts/release/commit-homebrew-cask.sh" \
  --tap-dir "${tap_dir}" \
  --version "${version}" \
  --dry-run >/dev/null

if git -C "${tap_dir}" diff --cached --quiet; then
  echo "Expected dry-run commit script to stage cask changes." >&2
  exit 1
fi

# The commit helper must also work on subsequent split-distribution releases.
git -C "${tap_dir}" -c user.name=test -c user.email=test@example.com commit -qm "migrate to cask"
"${repo_root}/scripts/release/update-homebrew-cask.sh" \
  --tap-dir "${tap_dir}" \
  --repository gi8lino/easybar \
  --tag "v9.8.8" \
  --version "9.8.8" \
  --sha "${sha}" \
  --calendar-agent-sha "${calendar_agent_sha}" \
  --network-agent-sha "${network_agent_sha}"
"${repo_root}/scripts/release/commit-homebrew-cask.sh" \
  --tap-dir "${tap_dir}" \
  --version "9.8.8" \
  --dry-run >/dev/null
