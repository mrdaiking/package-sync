# package-sync

Cross-device package backup and sync. Never forget what you installed.

## Features

- **Backup** — track packages from any manager (brew, cask, pip, npm, cargo, gem, go, apt, winget)
- **Auto-detect** — shell hook prompts when you install something new
- **Scan** — detect already-installed packages including DMG apps (`/Applications`)
- **Sync status** — `list` shows whether each package is synced to remote
- **Cross-device sync** — GitHub Gist keeps all machines in sync
- **Restore** — one command to install everything on a new machine

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/mrdaiking/package-sync/main/install.sh | bash
```

Then:

```bash
package-sync init          # add hook to your shell
package-sync sync setup    # create GitHub Gist for sync
```

> **Note:** `sync` requires the GitHub CLI. Install with `brew install gh && gh auth login`.

## Usage

```bash
# Add a package manually
package-sync add ripgrep brew
package-sync add visual-studio-code cask   # brew cask apps
package-sync add black pip
package-sync add prettier npm

# Scan all installed packages and pick which to track
package-sync scan

# List tracked packages (shows sync status)
package-sync list
package-sync list brew
package-sync list cask

# Install everything on a new machine
package-sync install

# Sync across devices
package-sync sync push     # push local → gist
package-sync sync pull     # pull gist → local
package-sync sync status   # see diff between devices

# Link a second device to same gist
package-sync sync setup <gist-id>
```

## Scan (detect already-installed packages)

`package-sync scan` finds packages installed before the hook was active:

```
Found 57 untracked package(s):

  [  1] (brew)  git
  [  2] (cask)  maccy
  [  3] (app)   Cursor
  [  4] (app)   Visual Studio Code
  [  5] (app)   Ollama
  ...

Options:
  a   — add all
  1,3 — add by number (comma-separated)
  q   — quit
```

Scans: `brew` formulae (top-level only), `brew` casks, `pip` (top-level), `npm -g`, `cargo`, `gem` (user-installed), `/Applications` (DMG/direct installs).

## Auto-detect (Usage 2)

After `package-sync init`, the shell hook watches for install commands:

```
$ brew install ripgrep

📦 package-sync: Add 'ripgrep' to your backup?
   Add now? [y/N]
```

Supports: `brew install`, `brew install --cask`, `pip`, `pip3`, `npm -g`, `cargo`, `apt`, `gem`, `go install`, `curl|bash`

## Cross-device notification (Usage 3)

On terminal open, other devices see:

```
📦 package-sync: 1 new package on MacBook-Pro (2026-05-07):
  + ripgrep (brew)
Run: package-sync sync pull
```

## Supported Package Managers

| Manager | Install command       | Platform     |
|---------|-----------------------|--------------|
| brew    | `brew install`        | macOS, Linux |
| cask    | `brew install --cask` | macOS        |
| apt     | `apt install`         | Debian/Ubuntu|
| pip     | `pip install`         | All          |
| npm     | `npm install -g`      | All          |
| cargo   | `cargo install`       | All          |
| gem     | `gem install`         | All          |
| go      | `go install`          | All          |
| winget  | `winget install`      | Windows      |
| app     | DMG / direct download | macOS        |

> `app` entries are tracked for awareness. `package-sync install` will print a manual-install reminder for them.

## Requirements

- `jq` — JSON processing
- `gh` — GitHub CLI (for sync feature only)
- zsh or bash

## Troubleshooting

**`cp: ... and ... are identical` on install or init**

Fixed in latest version. Update:

```bash
curl -fsSL https://raw.githubusercontent.com/mrdaiking/package-sync/main/install.sh | bash
```

Or if already installed:

```bash
git -C ~/.package-sync pull
```

**`gh: command not found` when running sync**

```bash
brew install gh && gh auth login
```

**Apps like VSCode, Cursor, Ollama not detected by hook**

These are installed via DMG, not a package manager. Run `package-sync scan` to detect them from `/Applications`.
