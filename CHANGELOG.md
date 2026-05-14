# Changelog

All notable changes to package-sync are documented here.

## [Unreleased]

### Added
- `package-sync scan` detects apps installed via DMG / direct download from `/Applications` — VSCode, Cursor, Ollama, etc. now trackable as `app` manager type
- `cask` manager type distinct from `brew` — restores via `brew install --cask` correctly
- `cargo`, `gem`, `go` manager support in scan and restore
- `synced` column in `package-sync list` — shows whether each package has been pushed to remote
- `sync` commands now guard against missing `gh` CLI with a clear install message
- Install script warns when `gh` is not found (required for sync)

### Fixed
- `cp: ... and ... are identical` error on `install.sh` — self-copy of `shell.sh` removed
- Same `cp` error on `package-sync init` — copy now skipped when source equals destination
- `package-sync scan` showed ~400 packages including transitive deps — now uses `brew leaves`, `pip --not-required`, `gem --user-installed` for top-level only
- `brew install --cask` commands now correctly stored as `cask` manager (not `brew`)

---

## [0.1.0] — Initial Release

### Added
- `package-sync add <name> [manager]` — manually track a package
- `package-sync remove <name>` — untrack a package
- `package-sync list` — list all tracked packages
- `package-sync install` — restore all packages on a new machine
- `package-sync scan` — detect untracked installed packages
- `package-sync sync setup/push/pull/status` — GitHub Gist sync
- Shell hook (zsh + bash) — auto-prompts on `brew`, `pip`, `npm -g`, `cargo`, `apt`, `gem`, `go install`, `curl|bash`
- Windows support via `package-sync.ps1` (`winget`, `npm`, `scoop`)
- Cross-device notification on terminal open
