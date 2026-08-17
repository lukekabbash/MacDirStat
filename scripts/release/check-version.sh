#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

project="$(release_project_version)"
requested="$(release_normalize_version "${1:-v${project}}")"
[[ "${requested}" == "${project}" ]] || release_die "tag v${requested} does not match MARKETING_VERSION ${project}"

release_notes="${release_repo_root}/docs/releases/v${requested}.md"
[[ -f "${release_notes}" ]] || release_die "release notes are missing: ${release_notes}"

echo "Release metadata is consistent for v${requested}."
