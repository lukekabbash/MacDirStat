# Releasing Mac Directory Statistics

Every macOS release is built from its Git tag by `.github/workflows/release-macos.yml`. The workflow tests the Core package, compiles one universal `arm64` + `x86_64` app, signs it, packages a DMG and ZIP, verifies both packages, writes SHA-256 checksums, and publishes the GitHub release.

## Cut a release

1. Update `MARKETING_VERSION` in both app configurations and increment `CURRENT_PROJECT_VERSION` in `DiskVisualizer.xcodeproj/project.pbxproj`.
2. Add `docs/releases/vX.Y.Z.md` and update `CHANGELOG.md`.
3. Run `make release-check VERSION=X.Y.Z` and merge the version change into `main` through a passing PR.
4. From a clean, current `main`, create and push the annotated tag:

   ```bash
   git tag -a vX.Y.Z -m "Mac Directory Statistics vX.Y.Z"
   git push origin vX.Y.Z
   ```

5. Watch the **Release macOS** workflow. It publishes these assets:

   - `Mac-Directory-Statistics-vX.Y.Z-macOS-universal.dmg`
   - `Mac-Directory-Statistics-vX.Y.Z-macOS-universal.zip`
   - `SHA256SUMS.txt`

The scripts refuse version mismatches and existing local artifacts. A local release build uses `make release-local VERSION=X.Y.Z` and requires a full Xcode installation selected with `xcode-select`.

## Developer ID signing and notarization

Without Apple credentials, the workflow deliberately uses an ad-hoc signature. The app remains intact and sandboxed, but another Mac requires a one-time **Control-click → Open** because Gatekeeper cannot establish an Apple-notarized publisher.

For normal double-click installation, add these GitHub Actions secrets:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64-encoded Developer ID Application `.p12` certificate and private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting that `.p12` |
| `APPLE_API_PRIVATE_KEY` | Contents of the App Store Connect `AuthKey_…p8` private key |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |

When all signing and API-key secrets are present, the same workflow imports an ephemeral keychain, signs with hardened runtime, notarizes and staples the app, signs/notarizes/staples the DMG, and verifies both with Gatekeeper. Secrets never enter the repository or release assets.

## Failure and recovery

- A failed workflow never moves or deletes an installed app; it operates only in the runner workspace.
- A tag whose version differs from the Xcode project fails before compilation.
- Re-running a successful tag replaces that release’s three assets rather than creating a second release.
- Do not move an existing version tag to different source. Fix forward with the next patch version.
