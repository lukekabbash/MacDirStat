#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

release_require_command gh

version="$(release_normalize_version "${1:-}")"
tag="v${version}"
output_dir="$(release_output_dir)"
stem="$(release_artifact_stem "${tag}")"
notes="${release_repo_root}/docs/releases/${tag}.md"
assets=(
  "${output_dir}/${stem}.dmg"
  "${output_dir}/${stem}.zip"
  "${output_dir}/SHA256SUMS.txt"
)

[[ -f "${notes}" ]] || release_die "release notes are missing: ${notes}"
for asset in "${assets[@]}"; do
  [[ -f "${asset}" ]] || release_die "release asset is missing: ${asset}"
done

if gh release view "${tag}" >/dev/null 2>&1; then
  gh release upload "${tag}" "${assets[@]}" --clobber
  gh release edit "${tag}" --title "Mac Directory Statistics ${tag}" --notes-file "${notes}" --latest
else
  gh release create "${tag}" "${assets[@]}" \
    --verify-tag \
    --title "Mac Directory Statistics ${tag}" \
    --notes-file "${notes}" \
    --latest
fi

gh release view "${tag}" --json url,tagName,name,isDraft,isPrerelease,publishedAt
