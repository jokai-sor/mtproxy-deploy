# Changelog

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
