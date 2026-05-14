#!/usr/bin/env bash
# package-sync — cross-device package backup & sync

set -euo pipefail

PKGSYNC_DIR="${PKGSYNC_DIR:-$HOME/.package-sync}"
PACKAGES_FILE="$PKGSYNC_DIR/packages.json"
CONFIG_FILE="$PKGSYNC_DIR/config.json"
VERSION="0.1.0"

_ensure_init() {
  if [[ ! -f "$PACKAGES_FILE" ]]; then
    echo '{"version":"'"$VERSION"'","packages":[]}' > "$PACKAGES_FILE"
  fi
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo '{"gist_id":"","device":"'"$(hostname -s)"'"}' > "$CONFIG_FILE"
  fi
}

cmd_init() {
  mkdir -p "$PKGSYNC_DIR"
  _ensure_init

  local shell_rc=""
  case "$SHELL" in
    */zsh)  shell_rc="$HOME/.zshrc" ;;
    */bash) shell_rc="$HOME/.bashrc" ;;
    *)      echo "Unsupported shell: $SHELL. Add hook manually."; return 1 ;;
  esac

  local hook_line='source "$HOME/.package-sync/hooks/shell.sh"'
  if grep -qF "package-sync" "$shell_rc" 2>/dev/null; then
    echo "Hook already in $shell_rc"
  else
    echo "" >> "$shell_rc"
    echo "# package-sync hook" >> "$shell_rc"
    echo "$hook_line" >> "$shell_rc"
    echo "Hook added to $shell_rc"
  fi

  # Resolve real script dir (handles symlinks)
  local src="$0"
  while [[ -L "$src" ]]; do src="$(readlink "$src")"; done
  local script_dir; script_dir="$(cd "$(dirname "$src")" && pwd)"

  mkdir -p "$PKGSYNC_DIR/hooks"
  [[ "$script_dir" != "$PKGSYNC_DIR" ]] && cp "$script_dir/hooks/shell.sh" "$PKGSYNC_DIR/hooks/shell.sh"
  [[ "$script_dir" != "$PKGSYNC_DIR" ]] && cp "$script_dir/hooks/notify.sh" "$PKGSYNC_DIR/hooks/notify.sh"

  echo "Initialized. Restart terminal or run: source $shell_rc"
}

cmd_add() {
  local name="${1:-}"
  local manager="${2:-brew}"
  local url="${3:-}"
  [[ -z "$name" ]] && { echo "Usage: package-sync add <name> [manager] [url]"; exit 1; }

  _ensure_init

  local platform
  platform="$(uname -s | tr '[:upper:]' '[:lower:]')"
  local device
  device="$(jq -r '.device' "$CONFIG_FILE" 2>/dev/null || hostname -s)"
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Check duplicate
  local exists
  exists="$(jq --arg n "$name" --arg m "$manager" \
    '[.packages[] | select(.name==$n and .manager==$m)] | length' \
    "$PACKAGES_FILE")"
  if [[ "$exists" -gt 0 ]]; then
    echo "$name ($manager) already tracked."
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  jq --arg n "$name" --arg m "$manager" --arg p "$platform" \
     --arg d "$device" --arg t "$timestamp" --arg u "$url" \
    '.packages += [{"name":$n,"manager":$m,"platform":$p,"device":$d,"added":$t,"synced":false} + (if $u != "" then {"url":$u} else {} end)]' \
    "$PACKAGES_FILE" > "$tmp" && mv "$tmp" "$PACKAGES_FILE"

  if [[ -n "$url" ]]; then
    echo "Added: $name (curl) → $url"
  else
    echo "Added: $name ($manager)"
  fi
}

cmd_remove() {
  local name="${1:-}"
  local manager="${2:-}"
  [[ -z "$name" ]] && { echo "Usage: package-sync remove <name> [manager]"; exit 1; }

  _ensure_init

  local tmp
  tmp="$(mktemp)"
  if [[ -n "$manager" ]]; then
    jq --arg n "$name" --arg m "$manager" \
      'del(.packages[] | select(.name==$n and .manager==$m))' \
      "$PACKAGES_FILE" > "$tmp"
  else
    jq --arg n "$name" \
      'del(.packages[] | select(.name==$n))' \
      "$PACKAGES_FILE" > "$tmp"
  fi
  mv "$tmp" "$PACKAGES_FILE"
  echo "Removed: $name"
}

cmd_list() {
  _ensure_init
  local filter="${1:-all}"

  case "$filter" in
    all)
      jq -r '.packages[] | "\(.manager)\t\(.name)\t[\(.platform)] — \(.device) @ \(.added)\(if .url then " | \(.url)" else "" end)\t\(if .synced == true then "synced" else "unsynced" end)"' \
        "$PACKAGES_FILE" | sort | column -t -s $'\t'
      ;;
    brew|cask|apt|pip|npm|cargo|gem|go|winget)
      jq -r --arg m "$filter" \
        '.packages[] | select(.manager==$m) | "\(.name)"' \
        "$PACKAGES_FILE"
      ;;
    *)
      echo "Usage: package-sync list [all|brew|cask|apt|pip|npm|cargo|gem|go|winget]"
      ;;
  esac
}

cmd_install() {
  _ensure_init
  local platform
  platform="$(uname -s | tr '[:upper:]' '[:lower:]')"

  echo "Installing packages for platform: $platform"

  while IFS=$'\t' read -r manager name url; do
    echo "→ [$manager] $name"
    case "$manager" in
      brew)   brew install "$name" 2>/dev/null || echo "  SKIP: $name" ;;
      cask)   brew install --cask "$name" 2>/dev/null || echo "  SKIP: $name" ;;
      pip)    pip3 install "$name" ;;
      npm)    npm install -g "$name" ;;
      cargo)  cargo install "$name" ;;
      gem)    gem install "$name" ;;
      go)     go install "$name" ;;
      apt)    sudo apt-get install -y "$name" ;;
      curl)
        if [[ -n "$url" ]]; then
          echo "  Running: curl -fsSL $url | bash"
          curl -fsSL "$url" | bash
        else
          echo "  SKIP: $name — no URL stored. Install manually."
        fi
        ;;
      *)      echo "  Unknown manager: $manager. Skip $name." ;;
    esac
  done < <(jq -r --arg p "$platform" \
    '.packages[] | select(.platform==$p or .platform=="all") | "\(.manager)\t\(.name)\t\(.url // "")"' \
    "$PACKAGES_FILE")

  echo "Done."
}

cmd_sync() {
  if ! command -v gh &>/dev/null; then
    echo "Error: 'gh' (GitHub CLI) required for sync. Install:"
    echo "  brew install gh && gh auth login"
    exit 1
  fi
  _ensure_init
  local subcmd="${1:-push}"
  local gist_id
  gist_id="$(jq -r '.gist_id' "$CONFIG_FILE")"

  case "$subcmd" in
    setup)
      # Create new gist or link existing
      local input_id="${2:-}"
      if [[ -n "$input_id" ]]; then
        jq --arg id "$input_id" '.gist_id = $id' "$CONFIG_FILE" > "$(mktemp)" && \
          mv "$(mktemp)" "$CONFIG_FILE"
        # Re-do properly
        local tmp; tmp="$(mktemp)"
        jq --arg id "$input_id" '.gist_id = $id' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        echo "Linked gist: $input_id"
      else
        # Create new private gist
        local new_id
        new_id="$(gh gist create "$PACKAGES_FILE" \
          --desc "package-sync backup" \
          --filename "packages.json" \
          | grep -oE '[a-f0-9]{32}')"
        local tmp; tmp="$(mktemp)"
        jq --arg id "$new_id" '.gist_id = $id' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        echo "Created gist: $new_id"
      fi
      ;;
    push)
      [[ -z "$gist_id" || "$gist_id" == "null" ]] && \
        { echo "No gist configured. Run: package-sync sync setup"; exit 1; }
      local tmp_push; tmp_push="$(mktemp)"
      jq '[.packages[] |= (.synced = true)] | {version,packages}' "$PACKAGES_FILE" > "$tmp_push" 2>/dev/null \
        || jq '.packages[] |= (.synced = true)' "$PACKAGES_FILE" > "$tmp_push"
      gh gist edit "$gist_id" --filename packages.json "$tmp_push"
      mv "$tmp_push" "$PACKAGES_FILE"
      echo "Pushed to gist: $gist_id"
      ;;
    pull)
      [[ -z "$gist_id" || "$gist_id" == "null" ]] && \
        { echo "No gist configured. Run: package-sync sync setup"; exit 1; }
      local tmp; tmp="$(mktemp)"
      gh api "/gists/$gist_id" --jq '.files["packages.json"].content' > "$tmp" 2>/dev/null \
        || { echo "Failed to fetch gist. Check: gh auth status"; rm "$tmp"; exit 1; }
      jq . "$tmp" &>/dev/null || { echo "Remote content invalid JSON. Run: package-sync sync push first."; rm "$tmp"; exit 1; }
      local tmp_pull; tmp_pull="$(mktemp)"
      jq '.packages[] |= (.synced = true)' "$tmp" > "$tmp_pull" && mv "$tmp_pull" "$PACKAGES_FILE"
      rm -f "$tmp"
      echo "Pulled from gist: $gist_id"
      ;;
    status)
      [[ -z "$gist_id" || "$gist_id" == "null" ]] && \
        { echo "No gist configured."; exit 1; }
      local remote_tmp; remote_tmp="$(mktemp)"
      gh api "/gists/$gist_id" --jq '.files["packages.json"].content' > "$remote_tmp" 2>/dev/null \
        || { echo "Failed to fetch gist. Check: gh auth status"; rm "$remote_tmp"; exit 1; }
      jq . "$remote_tmp" &>/dev/null || { echo "Remote content invalid JSON. Run: package-sync sync push first."; rm "$remote_tmp"; exit 1; }
      echo "=== Remote packages not on this device ==="
      comm -13 \
        <(jq -r '.packages[].name' "$PACKAGES_FILE" 2>/dev/null | sort) \
        <(jq -r '.packages[].name' "$remote_tmp" | sort) \
        | sed 's/^/  + /'
      echo "=== Local packages not on remote ==="
      comm -23 \
        <(jq -r '.packages[].name' "$PACKAGES_FILE" 2>/dev/null | sort) \
        <(jq -r '.packages[].name' "$remote_tmp" | sort) \
        | sed 's/^/  + /'
      rm "$remote_tmp"
      ;;
    *)
      echo "Usage: package-sync sync [setup [gist-id]|push|pull|status]"
      ;;
  esac
}

cmd_scan() {
  _ensure_init

  local tracked_names
  tracked_names="$(jq -r '.packages[].name' "$PACKAGES_FILE" 2>/dev/null | sort)"

  # Collect untracked packages as "manager:name" pairs
  local untracked=()

  # brew formulae
  if command -v brew &>/dev/null; then
    while IFS= read -r pkg; do
      [[ -z "$pkg" ]] && continue
      echo "$tracked_names" | grep -qx "$pkg" || untracked+=("brew:$pkg")
    done < <(brew list --formula 2>/dev/null)

    # brew casks
    while IFS= read -r pkg; do
      [[ -z "$pkg" ]] && continue
      echo "$tracked_names" | grep -qx "$pkg" || untracked+=("cask:$pkg")
    done < <(brew list --cask 2>/dev/null)
  fi

  # pip
  if command -v pip3 &>/dev/null; then
    while IFS= read -r pkg; do
      [[ -z "$pkg" ]] && continue
      local name; name="$(echo "$pkg" | cut -d= -f1 | tr '[:upper:]' '[:lower:]')"
      echo "$tracked_names" | grep -qix "$name" || untracked+=("pip:$name")
    done < <(pip3 list --format=freeze 2>/dev/null)
  fi

  # npm global
  if command -v npm &>/dev/null; then
    while IFS= read -r pkg; do
      [[ -z "$pkg" ]] && continue
      echo "$tracked_names" | grep -qx "$pkg" || untracked+=("npm:$pkg")
    done < <(npm list -g --depth=0 --parseable 2>/dev/null | tail -n +2 | xargs -I{} basename {} 2>/dev/null)
  fi

  # cargo
  if command -v cargo &>/dev/null; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local name; name="$(echo "$line" | awk '{print $1}')"
      echo "$tracked_names" | grep -qx "$name" || untracked+=("cargo:$name")
    done < <(cargo install --list 2>/dev/null | grep -E '^[a-z]')
  fi

  # gem
  if command -v gem &>/dev/null; then
    while IFS= read -r pkg; do
      [[ -z "$pkg" ]] && continue
      local name; name="$(echo "$pkg" | awk '{print $1}')"
      echo "$tracked_names" | grep -qx "$name" || untracked+=("gem:$name")
    done < <(gem list --no-versions 2>/dev/null)
  fi

  if [[ ${#untracked[@]} -eq 0 ]]; then
    echo "All installed packages already tracked."
    return 0
  fi

  echo ""
  echo "Found ${#untracked[@]} untracked package(s):"
  echo ""

  local i=1
  for entry in "${untracked[@]}"; do
    local mgr="${entry%%:*}"
    local pkg="${entry#*:}"
    printf "  [%3d] %-12s %s\n" "$i" "($mgr)" "$pkg"
    ((i++))
  done

  echo ""
  echo "Options:"
  echo "  a   — add all"
  echo "  1,3 — add by number (comma-separated)"
  echo "  q   — quit"
  echo ""
  read -r -p "Choice: " choice

  case "$choice" in
    q|Q|"") echo "Skipped." ;;
    a|A)
      for entry in "${untracked[@]}"; do
        local mgr="${entry%%:*}"
        local pkg="${entry#*:}"
        cmd_add "$pkg" "$mgr"
      done
      ;;
    *)
      IFS=',' read -ra indices <<< "$choice"
      for idx in "${indices[@]}"; do
        idx="$(echo "$idx" | tr -d ' ')"
        if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#untracked[@]} )); then
          local entry="${untracked[$((idx-1))]}"
          local mgr="${entry%%:*}"
          local pkg="${entry#*:}"
          cmd_add "$pkg" "$mgr"
        else
          echo "Invalid: $idx — skip"
        fi
      done
      ;;
  esac
}

cmd_help() {
  cat <<EOF
package-sync v$VERSION — cross-device package backup & sync

Commands:
  init                        Set up hooks in your shell
  add <name> [manager]        Track a package (default manager: brew)
  remove <name> [manager]     Stop tracking a package
  list [manager]              List tracked packages
  scan                        Scan installed packages, add untracked ones
  install                     Install all packages on new device
  sync setup [gist-id]        Create or link GitHub Gist for sync
  sync push                   Push local list to Gist
  sync pull                   Pull list from Gist
  sync status                 Show diff between local and remote

Supported managers: brew, cask, apt, pip, npm, cargo, gem, go, winget

EOF
}

main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    init)    cmd_init "$@" ;;
    add)     cmd_add "$@" ;;
    remove)  cmd_remove "$@" ;;
    list)    cmd_list "$@" ;;
    scan)    cmd_scan "$@" ;;
    install) cmd_install "$@" ;;
    sync)    cmd_sync "$@" ;;
    --version|-v) echo "package-sync v$VERSION" ;;
    help|--help|-h|*) cmd_help ;;
  esac
}

main "$@"
