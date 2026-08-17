#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

version="$(release_normalize_version "${1:-}")"
tag="v${version}"
output_dir="$(release_output_dir)"
stem="$(release_artifact_stem "${tag}")"
zip_name="${stem}.zip"
dmg_name="${stem}.dmg"

[[ -f "${output_dir}/${zip_name}" ]] || release_die "missing ${zip_name}"
[[ -f "${output_dir}/${dmg_name}" ]] || release_die "missing ${dmg_name}"

(
  cd "${output_dir}"
  shasum -a 256 "${dmg_name}" "${zip_name}" > SHA256SUMS.txt
)

echo "Wrote ${output_dir}/SHA256SUMS.txt."
