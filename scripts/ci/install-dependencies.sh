#!/usr/bin/env bash
# Install development and CI dependencies.
set -euo pipefail

# Print supported command-line arguments.
usage() {
  cat >&2 <<'EOF_USAGE'
Usage: scripts/ci/install-dependencies.sh <test|release|format|lua|imagemagick|librsvg> [...]

Modes:
  test         Install dependencies needed for tests.
  release      Install dependencies needed for release packaging.
  format       Install dependencies needed for source-format checks.
  lua          Install Lua only.
  imagemagick  Install ImageMagick only.
  librsvg      Install librsvg only.

Environment:
  HOMEBREW_TRUST_TAPS  Space-separated installed taps to trust before installs.
                       Default: aws/tap. Set to empty to skip.
EOF_USAGE
}

if [ "$#" -eq 0 ]; then
  set -- test
fi

need_lua=false
need_imagemagick=false
need_librsvg=false
need_stylua=false

for mode in "$@"; do
  case "$mode" in
    test|lua)
      need_lua=true
      ;;
    release)
      need_lua=true
      need_imagemagick=true
      need_librsvg=true
      ;;
    format)
      need_lua=true
      need_stylua=true
      ;;
    imagemagick)
      need_imagemagick=true
      ;;
    librsvg)
      need_librsvg=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown dependency mode: $mode" >&2
      usage
      exit 2
      ;;
  esac
done

# Mark installed Homebrew taps as trusted repositories.
trust_installed_taps() {
  if ! command -v brew >/dev/null 2>&1; then
    return 0
  fi

  if ! brew help trust >/dev/null 2>&1; then
    return 0
  fi

  local taps="${HOMEBREW_TRUST_TAPS-aws/tap}"
  if [ -z "$taps" ]; then
    return 0
  fi

  local installed_taps
  installed_taps="$(brew tap)"

  local tap
  for tap in $taps; do
    if printf '%s\n' "$installed_taps" | grep -Fxq "$tap"; then
      echo "Trusting Homebrew tap: $tap"
      brew trust "$tap"
    fi
  done
}

# Install a command only when it is unavailable.
install_if_missing() {
  local command_name="$1"
  local formula="$2"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install "$formula"
  fi
}

trust_installed_taps

if [ "$need_imagemagick" = true ]; then
  install_if_missing magick imagemagick
  image_convert="$(command -v magick)"

  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "IMAGE_CONVERT=${image_convert}" >>"$GITHUB_ENV"
  else
    echo "IMAGE_CONVERT=${image_convert}"
  fi

  magick -version
fi

if [ "$need_librsvg" = true ]; then
  install_if_missing rsvg-convert librsvg
  svg_convert="$(command -v rsvg-convert)"

  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "SVG_CONVERT=${svg_convert}" >>"$GITHUB_ENV"
  else
    echo "SVG_CONVERT=${svg_convert}"
  fi

  rsvg-convert --version
fi

if [ "$need_lua" = true ]; then
  install_if_missing lua lua
  lua -v
fi

if [ "$need_stylua" = true ]; then
  install_if_missing stylua stylua
  stylua --version
fi
