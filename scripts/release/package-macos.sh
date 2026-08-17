#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

release_require_command ditto
release_require_command hdiutil

version="$(release_normalize_version "${1:-}")"
tag="v${version}"
build_dir="$(release_build_dir)"
output_dir="$(release_output_dir)"
app_path="${build_dir}/$(release_app_name)"
stem="$(release_artifact_stem "${tag}")"
zip_path="${output_dir}/${stem}.zip"
dmg_path="${output_dir}/${stem}.dmg"

[[ -d "${app_path}" ]] || release_die "release app is missing: ${app_path}"
[[ ! -e "${zip_path}" && ! -e "${dmg_path}" ]] || release_die "refusing to overwrite existing release artifacts"
mkdir -p "${output_dir}"

staging="$(mktemp -d "${TMPDIR:-/tmp}/macdirstat-package.XXXXXX")"
trap 'release_cleanup_tree "${staging}"' EXIT
ditto "${app_path}" "${staging}/$(release_app_name)"
ln -s /Applications "${staging}/Applications"

ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${zip_path}"
hdiutil create \
  -volname "Mac Directory Statistics ${version}" \
  -srcfolder "${staging}" \
  -format UDZO \
  -ov \
  "${dmg_path}"

if [[ -n "${MACOS_SIGNING_IDENTITY:-}" && "${MACOS_SIGNING_IDENTITY}" != "-" ]]; then
  signing_args=(--force --timestamp --sign "${MACOS_SIGNING_IDENTITY}")
  if [[ -n "${MACOS_SIGNING_KEYCHAIN:-}" ]]; then
    signing_args+=(--keychain "${MACOS_SIGNING_KEYCHAIN}")
  fi
  codesign "${signing_args[@]}" "${dmg_path}"
fi

echo "Packaged ${zip_path}"
echo "Packaged ${dmg_path}"
