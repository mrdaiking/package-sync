# package-sync

Cross-device package backup and sync. Never forget what you installed.

## Features

- **Backup** — track packages from any manager (brew, pip, npm, cargo, apt, winget)
- **Auto-detect** — shell hook prompts when you install something new
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

## Usage

```bash
# Add a package manually
package-sync add ripgrep brew
package-sync add black pip
package-sync add prettier npm

# List tracked packages
package-sync list
package-sync list brew

# Install everything on a new machine
package-sync install

# Sync across devices
package-sync sync push     # push local → gist
package-sync sync pull     # pull gist → local
package-sync sync status   # see diff between devices

# Link a second device to same gist
package-sync sync setup <gist-id>
```

## Auto-detect (Usage 2)

After `package-sync init`, the shell hook watches for install commands:

```
$ brew install ripgrep

📦 package-sync: Add 'ripgrep' to your backup?
   Run: package-sync add ripgrep brew
   Add now? [y/N]
```

Supports: `brew`, `pip`, `pip3`, `npm -g`, `cargo`, `apt`, `gem`, `curl|bash`

## Cross-device notification (Usage 3)

On terminal open, other devices see:

```
📦 package-sync: 1 new package on MacBook-Pro (2026-05-07):
  + ripgrep (brew)
Run: package-sync sync pull
```

## Supported Package Managers

| Manager | Platform |
|---------|----------|
| brew    | macOS, Linux |
| apt     | Debian/Ubuntu |
| pip     | All |
| npm -g  | All |
| cargo   | All |
| winget  | Windows |
| gem     | All |

## Requirements

- `jq` — JSON processing
- `gh` — GitHub CLI (for sync feature only)
- zsh or bash


