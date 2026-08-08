#!/usr/bin/env bash
set -euo pipefail

tap_dir=""
repository="${GITHUB_REPOSITORY:-easybar-app/easybar}"
tag=""
version=""
sha=""
calendar_agent_sha=""
network_agent_sha=""

while [ "$#" -gt 0 ]; do
  case "$1" in
  --tap-dir) tap_dir="${2:?missing value for --tap-dir}"; shift 2 ;;
  --repository) repository="${2:?missing value for --repository}"; shift 2 ;;
  --tag) tag="${2:?missing value for --tag}"; shift 2 ;;
  --version) version="${2:?missing value for --version}"; shift 2 ;;
  --sha) sha="${2:?missing value for --sha}"; shift 2 ;;
  --calendar-agent-sha) calendar_agent_sha="${2:?missing value for --calendar-agent-sha}"; shift 2 ;;
  --network-agent-sha) network_agent_sha="${2:?missing value for --network-agent-sha}"; shift 2 ;;
  *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "${tap_dir}" ] || [ -z "${version}" ] || [ -z "${sha}" ] || \
  [ -z "${calendar_agent_sha}" ] || [ -z "${network_agent_sha}" ]; then
  echo "Usage: $0 --tap-dir DIR --version VERSION --sha SHA --calendar-agent-sha SHA --network-agent-sha SHA [--repository OWNER/REPO] [--tag TAG]" >&2
  exit 2
fi

if [ -z "${tag}" ]; then
  tag="v${version}"
fi

cask_dir="${tap_dir}/Casks"
formula_dir="${tap_dir}/Formula"
easybar_cask_file="${cask_dir}/easybar.rb"
calendar_agent_formula_file="${formula_dir}/easybar-calendar-agent.rb"
network_agent_formula_file="${formula_dir}/easybar-network-agent.rb"
asset_url="https://github.com/${repository}/releases/download/${tag}/EasyBar-${version}.zip"

mkdir -p "${cask_dir}" "${formula_dir}"

cat >"${easybar_cask_file}" <<EOF_CASK
cask "easybar" do
  version "${version}"
  sha256 "${sha}"

  url "${asset_url}"
  name "EasyBar"
  desc "Scriptable macOS status bar with SwiftUI and Lua widgets"
  homepage "https://github.com/${repository}"

  depends_on formula: [
    "easybar-calendar-agent",
    "easybar-network-agent",
    "lua",
  ]
  depends_on macos: :sonoma

  postflight do
    system "xattr", "-d", "com.apple.quarantine", "#{staged_path}/easybar"
    system "xattr", "-dr", "com.apple.quarantine", "#{appdir}/EasyBar.app"
    system "#{HOMEBREW_PREFIX}/bin/brew", "services", "restart", "easybar-calendar-agent"
    system "#{HOMEBREW_PREFIX}/bin/brew", "services", "restart", "easybar-network-agent"
  end

  uninstall_preflight do
    system "#{HOMEBREW_PREFIX}/bin/brew", "services", "stop", "easybar-calendar-agent"
    system "#{HOMEBREW_PREFIX}/bin/brew", "services", "stop", "easybar-network-agent"
  end

  app "EasyBar.app"
  binary "easybar"

  zap trash: [
    "~/.config/easybar",
    "~/.local/state/easybar",
  ]
end
EOF_CASK

write_agent_formula() {
  local file="$1"
  local class_name="$2"
  local description="$3"
  local app_name="$4"
  local log_name="$5"
  local asset_name="$6"
  local asset_sha="$7"

  cat >"$file" <<EOF_FORMULA
class ${class_name} < Formula
  desc "${description}"
  homepage "https://github.com/${repository}"
  url "https://github.com/${repository}/releases/download/${tag}/${asset_name}-${version}.zip"
  sha256 "${asset_sha}"
  license "Apache-2.0"
  version "${version}"

  depends_on macos: :sonoma

  def install
    libexec.install "${app_name}.app"
    system "xattr", "-dr", "com.apple.quarantine", libexec/"${app_name}.app"
    (var/"log/easybar").mkpath
  end

  service do
    run [opt_libexec/"${app_name}.app/Contents/MacOS/${app_name}"]
    environment_variables PATH: std_service_path_env, LANG: "en_US.UTF-8"
    keep_alive successful_exit: false
    process_type :interactive
    working_dir HOMEBREW_PREFIX
    log_path var/"log/easybar/${log_name}.out.log"
    error_log_path var/"log/easybar/${log_name}.err.log"
  end

  test do
    assert_predicate libexec/"${app_name}.app", :exist?
  end
end
EOF_FORMULA
}

write_agent_formula \
  "${calendar_agent_formula_file}" \
  "EasybarCalendarAgent" \
  "Calendar EventKit helper service for EasyBar" \
  "EasyBarCalendarAgent" \
  "calendar-agent" \
  "EasyBarCalendarAgent" \
  "${calendar_agent_sha}"

write_agent_formula \
  "${network_agent_formula_file}" \
  "EasybarNetworkAgent" \
  "Wi-Fi and network helper service for EasyBar" \
  "EasyBarNetworkAgent" \
  "network-agent" \
  "EasyBarNetworkAgent" \
  "${network_agent_sha}"

rm -f "${formula_dir}/easybar.rb"
