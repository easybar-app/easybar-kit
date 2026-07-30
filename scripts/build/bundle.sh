#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "bundle failed at line $LINENO: $BASH_COMMAND" >&2' ERR

usage() {
  cat >&2 <<'EOF_USAGE'
Usage: scripts/build/bundle.sh [options]

Options:
  --arch <arm64|x86_64|universal>       Build architecture. Default: universal
  --version <version>                   Version stamped into bundles. Default: dev
  --bundle-id <id>                      App bundle identifier. Default: com.gi8lino.EasyBar
  --codesign-identity <identity>        Codesign identity. Default: -
  --notarytool-profile <profile>        Notarytool keychain profile. Default: empty
  --notary-submit <0|1>                 Submit for notarization. Default: 0
  --clean-build <0|1>                   Also remove .build before bundling. Default: CLEAN_BUILD or 0
  --dist-dir <dir>                      Distribution directory. Default: dist
EOF_USAGE
}

arch="${ARCH:-universal}"
version="${VERSION:-dev}"
bundle_id="${BUNDLE_ID:-com.gi8lino.EasyBar}"
codesign_identity="${CODESIGN_IDENTITY:--}"
notarytool_profile="${NOTARYTOOL_PROFILE:-}"
notary_submit="${NOTARY_SUBMIT:-0}"
clean_build="${CLEAN_BUILD:-0}"
dist_dir="${DIST_DIR:-dist}"
image_convert="${IMAGE_CONVERT:-magick}"
icon_font="${ICON_FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}"

while [ "$#" -gt 0 ]; do
  case "$1" in
  --arch)
    arch="${2:?missing value for --arch}"
    shift 2
    ;;
  --version)
    version="${2:?missing value for --version}"
    shift 2
    ;;
  --bundle-id)
    bundle_id="${2:?missing value for --bundle-id}"
    shift 2
    ;;
  --codesign-identity)
    codesign_identity="${2:?missing value for --codesign-identity}"
    shift 2
    ;;
  --notarytool-profile)
    if [ "$#" -lt 2 ]; then
      echo "Missing value for --notarytool-profile" >&2
      exit 2
    fi
    notarytool_profile="$2"
    shift 2
    ;;
  --notary-submit)
    notary_submit="${2:?missing value for --notary-submit}"
    shift 2
    ;;
  --clean-build)
    clean_build="${2:?missing value for --clean-build}"
    shift 2
    ;;
  --dist-dir)
    dist_dir="${2:?missing value for --dist-dir}"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    usage
    exit 2
    ;;
  esac
done

case "$arch" in
arm64 | x86_64 | universal) ;;
*)
  echo "Unsupported architecture '$arch'. Use arm64, x86_64, or universal." >&2
  exit 2
  ;;
esac

case "$clean_build" in
0 | false | no)
  scripts/build/clean-dist-dir.sh "$dist_dir"
  ;;
1 | true | yes)
  scripts/build/clean-dist-dir.sh "$dist_dir"
  rm -rf .build
  ;;
*)
  echo "Unsupported clean build value '$clean_build'. Use 0 or 1." >&2
  exit 2
  ;;
esac

app_name="EasyBar"
app_product="EasyBar"
lua_runtime_product="EasyBarLuaRuntime"
calendar_agent_name="EasyBarCalendarAgent"
network_agent_name="EasyBarNetworkAgent"
cli_product="EasyBarCtl"
cli_exec="easybar"
resource_bundle_name="EasyBar_EasyBarApp.bundle"
themes_dir="themes"

app_bundle="$dist_dir/${app_name}.app"
app_contents="$app_bundle/Contents"
app_macos="$app_contents/MacOS"
app_resources="$app_contents/Resources"
app_resource_dir="$app_resources/$app_name"
app_themes_dir="$app_resources/Themes"
app_bin="$app_macos/$app_name"
lua_runtime_bin="$app_macos/$lua_runtime_product"
app_plist="$app_contents/Info.plist"
app_icon_file="$app_name"
app_icon_icns="$app_resources/${app_icon_file}.icns"

calendar_agent_bundle="$dist_dir/${calendar_agent_name}.app"
calendar_agent_contents="$calendar_agent_bundle/Contents"
calendar_agent_macos="$calendar_agent_contents/MacOS"
calendar_agent_resources="$calendar_agent_contents/Resources"
calendar_agent_bin="$calendar_agent_macos/$calendar_agent_name"
calendar_agent_plist="$calendar_agent_contents/Info.plist"
calendar_agent_icon_file="$calendar_agent_name"
calendar_agent_icon_icns="$calendar_agent_resources/${calendar_agent_icon_file}.icns"

network_agent_bundle="$dist_dir/${network_agent_name}.app"
network_agent_contents="$network_agent_bundle/Contents"
network_agent_macos="$network_agent_contents/MacOS"
network_agent_resources="$network_agent_contents/Resources"
network_agent_bin="$network_agent_macos/$network_agent_name"
network_agent_plist="$network_agent_contents/Info.plist"
network_agent_icon_file="$network_agent_name"
network_agent_icon_icns="$network_agent_resources/${network_agent_icon_file}.icns"

cli_bin="$dist_dir/$cli_exec"
notary_zip="$dist_dir/${app_name}-notarize.zip"

mkdir -p \
  "$app_macos" \
  "$app_resources" \
  "$calendar_agent_macos" \
  "$calendar_agent_resources" \
  "$network_agent_macos" \
  "$network_agent_resources" \
  "$dist_dir"

echo "Building release products for $arch"
scripts/build/build-products.sh release "$arch" --version "$version" \
  "$app_product=$app_bin" \
  "$lua_runtime_product=$lua_runtime_bin" \
  "$calendar_agent_name=$calendar_agent_bin" \
  "$network_agent_name=$network_agent_bin" \
  "$cli_product=$cli_bin"

echo "Copying bundled resources"
scripts/build/copy-resources.sh \
  release \
  "$arch" \
  "$resource_bundle_name" \
  "$app_bundle" \
  "$app_resource_dir" \
  "$themes_dir" \
  "$app_themes_dir" \
  "$version"

echo "Generating app icons"
scripts/assets/app_icons.sh "$image_convert" "$icon_font" "$dist_dir" \
  "packaging/easybar-icon.svg:$app_icon_icns" \
  "packaging/easybar-calendar-agent-icon.svg:$calendar_agent_icon_icns" \
  "packaging/easybar-network-agent-icon.svg:$network_agent_icon_icns"

echo "Stamping Info.plist files"
cp Sources/EasyBarApp/Info.plist "$app_plist"
cp Sources/EasyBarCalendarAgent/Info.plist "$calendar_agent_plist"
cp Sources/EasyBarNetworkAgent/Info.plist "$network_agent_plist"

scripts/build/stamp.py plist \
  --plist "$app_plist" \
  --bundle-id "$bundle_id" \
  --version "$version" \
  --executable "$app_name" \
  --name "$app_name" \
  --icon-file "$app_icon_file"

scripts/build/stamp.py plist \
  --plist "$calendar_agent_plist" \
  --version "$version" \
  --executable "$calendar_agent_name" \
  --name "$calendar_agent_name" \
  --icon-file "$calendar_agent_icon_file"

scripts/build/stamp.py plist \
  --plist "$network_agent_plist" \
  --version "$version" \
  --executable "$network_agent_name" \
  --name "$network_agent_name" \
  --icon-file "$network_agent_icon_file"

chmod +x \
  "$app_bin" \
  "$lua_runtime_bin" \
  "$calendar_agent_bin" \
  "$network_agent_bin" \
  "$cli_bin"

echo "Signing artifacts"
scripts/release/sign-artifacts.sh \
  "$codesign_identity" \
  "$app_bundle" \
  "$calendar_agent_bundle" \
  "$network_agent_bundle" \
  "$cli_bin"

echo "Notarizing artifacts when enabled"
scripts/release/notarize-app.sh \
  "$notary_submit" \
  "$codesign_identity" \
  "$notarytool_profile" \
  "$app_bundle" \
  "$notary_zip"

echo "Verifying bundle"
touch "$calendar_agent_bundle" "$network_agent_bundle" "$app_bundle"
scripts/build/verify-bundle.sh --arch "$arch" --version "$version" --dist-dir "$dist_dir"
