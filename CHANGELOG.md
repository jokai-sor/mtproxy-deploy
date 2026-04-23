# Changelog

## 0.3.0 - 2026-04-23

### Added

- Shell regression tests for install and uninstall helper logic
- Release-check commands in operations documentation
- Notes for single-host FakeTLS DNS behavior, including IPv6/AAAA caveats
- Russian operations and FakeTLS documentation

### Changed

- `install.sh` now restarts `mtg` after writing the binary, config, and systemd unit so upgrades
  are applied immediately
- `install.sh` now pins `mtg` `2.2.8` as the default install version while keeping
  `--mtg-version` as an explicit override
- FakeTLS secret reuse now compares the encoded domain instead of regenerating random secrets
- FakeTLS helper cleanup now reconciles existing nginx and `/etc/hosts` state before applying a new
  install mode
- `uninstall.sh` now supports source-based tests via a `main` entrypoint guard

### Fixed

- Re-running `install.sh` with an existing active service no longer leaves the old process running
  after an upgrade or config change
- Uninstall can remove legacy single-host FakeTLS side effects even when `faketls.env` is missing
- Reading `faketls.env` no longer clobbers the current install arguments during mode/domain changes
- `install_mtg` temporary-directory cleanup no longer fails under `set -u`

## 0.2.0 - 2026-03-13

Switch MTProxy implementation from build-from-source `mtproto-proxy` to `mtg` (9seconds/mtg).

### Changed

- `install.sh` now downloads the latest `mtg` binary from GitHub releases instead of cloning and
  compiling the official MTProxy C source
- Secret generated via `mtg generate-secret` and stored in `/etc/mtg/config.toml`
- systemd service renamed from `mtproxy` to `mtg`
- `uninstall.sh` updated to remove `mtg` binary and `/etc/mtg/` config directory
- README and docs updated to match current install flow

### Fixed

- Android Telegram clients can now connect via FakeTLS. The old `mtproto-proxy` filled the TLS
  Certificate record with random bytes; `mtg` relays the real certificate from the domain endpoint.
  iOS was unaffected but Android validates certificate content and rejected the fake bytes.

## 0.1.0 - 2026-03-09

Initial standalone release.

### Added

- standalone MTProxy deployment project
- `standard` install mode
- `faketls` install mode
- optional local nginx TLS-helper for FakeTLS
- uninstall script
- English and Russian README
- operations and FakeTLS documentation
