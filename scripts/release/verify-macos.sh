#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

release_require_command codesign
release_require_command hdiutil
release_require_command lipo
release_require_command plutil
release_require_command unzip

version="$(release_normalize_version "${1:-}")"
tag="v${version}"
output_dir="$(release_output_dir)"
build_dir="$(release_build_dir)"
stem="$(release_artifact_stem "${tag}")"
zip_path="${output_dir}/${stem}.zip"
dmg_path="${output_dir}/${stem}.dmg"
checksums="${output_dir}/SHA256SUMS.txt"
app_path="${build_dir}/$(release_app_name)"

[[ -f "${zip_path}" && -f "${dmg_path}" && -f "${checksums}" ]] || release_die "release artifact set is incomplete"
(
  cd "${output_dir}"
  shasum -a 256 -c "${checksums}"
)
unzip -tq "${zip_path}" >/dev/null
codesign --verify --deep --strict --verbose=2 "${app_path}"

bundle_version="$(plutil -extract CFBundleShortVersionString raw "${app_path}/Contents/Info.plist")"
[[ "${bundle_version}" == "${version}" ]] || release_die "app version ${bundle_version} does not match ${version}"

architectures="$(lipo -archs "${app_path}/Contents/MacOS/Mac Directory Statistics")"
for architecture in arm64 x86_64; do
  [[ " ${architectures} " == *" ${architecture} "* ]] || release_die "release executable is missing ${architecture}"
done

mount_point="$(mktemp -d "${TMPDIR:-/tmp}/macdirstat-mount.XXXXXX")"
attached=0
cleanup_mount() {
  if [[ "${attached}" == "1" ]]; then
    hdiutil detach "${mount_point}" -quiet || true
  fi
  release_cleanup_tree "${mount_point}"
}
trap cleanup_mount EXIT
hdiutil attach "${dmg_path}" -nobrowse -readonly -mountpoint "${mount_point}" -quiet
attached=1
mounted_app="${mount_point}/$(release_app_name)"
[[ -d "${mounted_app}" && -L "${mount_point}/Applications" ]] || release_die "DMG layout is incomplete"
codesign --verify --deep --strict --verbose=2 "${mounted_app}"

if [[ "${EXPECT_NOTARIZED:-0}" == "1" ]]; then
  spctl --assess --type execute --verbose=2 "${mounted_app}"
  spctl --assess --type open --context context:primary-signature --verbose=2 "${dmg_path}"
fi

echo "Verified v${version}: ${architectures}, ZIP, DMG, signatures, layout, and checksums."
