#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

release_require_command xcodebuild
release_require_command codesign
release_require_command lipo
release_require_command ditto

version="$(release_normalize_version "${1:-}")"
"${release_script_dir}/check-version.sh" "v${version}"

build_dir="$(release_build_dir)"
derived_data="${build_dir}/DerivedData"
app_path="${build_dir}/$(release_app_name)"

[[ ! -e "${app_path}" ]] || release_die "refusing to overwrite existing build: ${app_path}"
mkdir -p "${build_dir}"

xcodebuild \
  -project "${release_repo_root}/DiskVisualizer.xcodeproj" \
  -scheme DiskVisualizer \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${derived_data}" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

built_app="${derived_data}/Build/Products/Release/$(release_app_name)"
[[ -d "${built_app}" ]] || release_die "Xcode did not produce ${built_app}"
ditto "${built_app}" "${app_path}"

signing_identity="${MACOS_SIGNING_IDENTITY:--}"
if [[ "${signing_identity}" == "-" ]]; then
  codesign --force --deep --sign - \
    --entitlements "${release_repo_root}/DiskVisualizer/DiskVisualizer.entitlements" \
    "${app_path}"
  echo "Built an ad-hoc-signed universal app."
else
  signing_args=(--force --deep --options runtime --timestamp --sign "${signing_identity}")
  if [[ -n "${MACOS_SIGNING_KEYCHAIN:-}" ]]; then
    signing_args+=(--keychain "${MACOS_SIGNING_KEYCHAIN}")
  fi
  codesign "${signing_args[@]}" \
    --entitlements "${release_repo_root}/DiskVisualizer/DiskVisualizer.entitlements" \
    "${app_path}"
  echo "Built a Developer ID-signed universal app."
fi

codesign --verify --deep --strict --verbose=2 "${app_path}"

bundle_version="$(plutil -extract CFBundleShortVersionString raw "${app_path}/Contents/Info.plist")"
[[ "${bundle_version}" == "${version}" ]] || release_die "built app reports ${bundle_version}, expected ${version}"

executable="${app_path}/Contents/MacOS/Mac Directory Statistics"
architectures="$(lipo -archs "${executable}")"
for architecture in arm64 x86_64; do
  [[ " ${architectures} " == *" ${architecture} "* ]] || release_die "built executable is missing ${architecture}"
done

echo "Built $(release_app_name) ${version} for ${architectures}."
