#!/usr/bin/env bash

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

release_require_command xcrun
release_require_command ditto
release_require_command codesign

target="${1:-}"
[[ -e "${target}" ]] || release_die "notarization target is missing: ${target}"
[[ -n "${APPLE_API_KEY_PATH:-}" && -f "${APPLE_API_KEY_PATH}" ]] || release_die "APPLE_API_KEY_PATH is not configured"
[[ -n "${APPLE_API_KEY_ID:-}" ]] || release_die "APPLE_API_KEY_ID is not configured"
[[ -n "${APPLE_API_ISSUER_ID:-}" ]] || release_die "APPLE_API_ISSUER_ID is not configured"
[[ -n "${MACOS_SIGNING_IDENTITY:-}" && "${MACOS_SIGNING_IDENTITY}" != "-" ]] || release_die "Developer ID signing is required before notarization"

submission="${target}"
temporary=""
if [[ "${target}" == *.app ]]; then
  temporary="$(mktemp "${TMPDIR:-/tmp}/macdirstat-notary.XXXXXX.zip")"
  trap '[[ -z "${temporary}" ]] || find "${temporary}" -depth -delete' EXIT
  ditto -c -k --sequesterRsrc --keepParent "${target}" "${temporary}"
  submission="${temporary}"
elif [[ "${target}" == *.dmg ]]; then
  signing_args=(--force --timestamp --sign "${MACOS_SIGNING_IDENTITY}")
  if [[ -n "${MACOS_SIGNING_KEYCHAIN:-}" ]]; then
    signing_args+=(--keychain "${MACOS_SIGNING_KEYCHAIN}")
  fi
  codesign "${signing_args[@]}" "${target}"
else
  release_die "notarization supports .app or .dmg targets"
fi

xcrun notarytool submit "${submission}" \
  --key "${APPLE_API_KEY_PATH}" \
  --key-id "${APPLE_API_KEY_ID}" \
  --issuer "${APPLE_API_ISSUER_ID}" \
  --wait
xcrun stapler staple "${target}"
xcrun stapler validate "${target}"

echo "Notarized and stapled ${target}."
