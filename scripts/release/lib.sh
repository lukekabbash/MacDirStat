#!/usr/bin/env bash

set -euo pipefail

release_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
release_repo_root="$(cd "${release_script_dir}/../.." && pwd)"

release_die() {
  echo "release: $*" >&2
  exit 1
}

release_require_command() {
  command -v "$1" >/dev/null 2>&1 || release_die "required command not found: $1"
}

release_normalize_version() {
  local raw="${1:-}"
  raw="${raw#v}"
  [[ "${raw}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || release_die "expected a semantic version such as v0.1.0"
  printf '%s\n' "${raw}"
}

release_project_version() {
  local project="${release_repo_root}/DiskVisualizer.xcodeproj/project.pbxproj"
  local versions
  versions="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' "${project}" | sort -u)"
  [[ -n "${versions}" ]] || release_die "MARKETING_VERSION is missing from the Xcode project"
  [[ "$(printf '%s\n' "${versions}" | wc -l | tr -d ' ')" == "1" ]] || release_die "Xcode configurations disagree on MARKETING_VERSION"
  printf '%s\n' "${versions}"
}

release_output_dir() {
  printf '%s\n' "${RELEASE_OUTPUT_DIR:-${release_repo_root}/.release/output}"
}

release_build_dir() {
  printf '%s\n' "${RELEASE_BUILD_DIR:-${release_repo_root}/.release/build}"
}

release_app_name() {
  printf '%s\n' "Mac Directory Statistics.app"
}

release_artifact_stem() {
  local tag="$1"
  printf 'Mac-Directory-Statistics-%s-macOS-universal\n' "${tag}"
}

release_cleanup_tree() {
  local path="$1"
  [[ -n "${path}" && -d "${path}" ]] || return 0
  find "${path}" -depth -delete
}
