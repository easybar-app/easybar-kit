#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
widgets_dir="${1:-${repo_root}/widgets}"
manifest_path="${2:-${widgets_dir}/install-manifest.csv}"

fail() {
  echo "Widget layout check failed: $*" >&2
  exit 1
}

[ -d "${widgets_dir}" ] || fail "missing widgets directory: ${widgets_dir}"
[ -f "${manifest_path}" ] || fail "missing install manifest: ${manifest_path}"
[ -d "${widgets_dir}/integrations" ] || fail "missing integrations directory"
[ -d "${widgets_dir}/shared" ] || fail "missing shared directory"

for service in brew github gitlab tailscale wireguard; do
  [ -f "${widgets_dir}/integrations/${service}/README.md" ] \
    || fail "missing integrations/${service}/README.md"
done

for obsolete in \
  shared/brew_policy.lua \
  shared/brew/policy.lua \
  shared/secrets.lua; do
  [ ! -e "${widgets_dir}/${obsolete}" ] || fail "obsolete service-specific module remains in ${obsolete}"
done

entrypoints=()
dependencies=()
line_number=0
while IFS=';' read -r widget dependency extra || [ -n "${widget}${dependency}${extra}" ]; do
  line_number=$((line_number + 1))
  case "${widget}" in
    ''|'#'*) continue ;;
  esac

  [ -z "${extra}" ] || fail "manifest line ${line_number} must contain exactly two semicolon-separated fields"
  [ -n "${dependency}" ] || fail "manifest line ${line_number} has an empty dependency"

  case "${widget}" in
    */*|../*|*/../*|*/..)
      fail "manifest line ${line_number} has an invalid widget path: ${widget}"
      ;;
  esac
  case "${dependency}" in
    /*|../*|*/../*|*/..)
      fail "manifest line ${line_number} has an invalid dependency path: ${dependency}"
      ;;
  esac

  [ -f "${widgets_dir}/${widget}" ] || fail "manifest widget does not exist: ${widget}"
  [ -e "${widgets_dir}/${dependency}" ] || fail "manifest dependency does not exist: ${dependency}"

  entrypoints+=("${widget}")
  dependencies+=("${dependency}")
done <"${manifest_path}"

for wrapper in \
  brew.lua \
  brew-inbox.lua \
  github.lua \
  github-inbox.lua \
  gitlab.lua \
  gitlab-inbox.lua \
  tailscale.lua \
  wireguard.lua; do
  [ -f "${widgets_dir}/${wrapper}" ] || fail "missing top-level entrypoint: ${wrapper}"
  grep -Fq ')(easybar)' "${widgets_dir}/${wrapper}" \
    || fail "entrypoint does not delegate through a widget-scoped integration module: ${wrapper}"
done

printf 'Widget integration layout validated (%d manifest rows).\n' "${#entrypoints[@]}"
