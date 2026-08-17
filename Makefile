VERSION ?= 0.1.0

.PHONY: release-check release-local

release-check:
	@scripts/release/check-version.sh "v$(VERSION)"
	@scripts/release/lint-shell.sh

release-local: release-check
	@scripts/release/build-macos.sh "v$(VERSION)"
	@scripts/release/package-macos.sh "v$(VERSION)"
	@scripts/release/checksum-macos.sh "v$(VERSION)"
	@scripts/release/verify-macos.sh "v$(VERSION)"
