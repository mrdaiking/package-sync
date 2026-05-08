#!/usr/bin/env bash
# GitHub Gist sync backend

set -euo pipefail

PKGSYNC_DIR="${PKGSYNC_DIR:-$HOME/.package-sync}"
PACKAGES_FILE="$PKGSYNC_DIR/packages.json"
CONFIG_FILE="$PKGSYNC_DIR/config.json"

_require_gh() {
  command -v gh &>/dev/null || { echo "gh CLI not installed. Run: brew install gh"; exit 1; }
  gh auth status &>/dev/null || { echo "gh not authenticated. Run: gh auth login"; exit 1; }
}

_get_gist_id() {
  jq -r '.gist_id // empty' "$CONFIG_FILE" 2>/dev/null
}

gist_setup() {
  _require_gh
  local existing_id="${1:-}"

  if [[ -n "$existing_id" ]]; then
    local tmp; tmp="$(mktemp)"
    jq --arg id "$existing_id" '.gist_id = $id' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    echo "Linked to existing gist: $existing_id"
    return 0
  fi

  # Create new private gist
  local url
  url="$(gh gist create "$PACKAGES_FILE" \
    --desc "package-sync: $(hostname -s) package backup" \
    --filename "packages.json")"

  local new_id
  new_id="$(basename "$url")"

  local tmp; tmp="$(mktemp)"
  jq --arg id "$new_id" '.gist_id = $id' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
  echo "Created private gist: $new_id"
  echo "Share this ID with other devices: package-sync sync setup $new_id"
}

gist_push() {
  _require_gh
  local gist_id; gist_id="$(_get_gist_id)"
  [[ -z "$gist_id" ]] && { echo "No gist configured. Run: package-sync sync setup"; exit 1; }

  gh gist edit "$gist_id" --filename packages.json "$PACKAGES_FILE"
  echo "Pushed → gist:$gist_id"
}

gist_pull() {
  _require_gh
  local gist_id; gist_id="$(_get_gist_id)"
  [[ -z "$gist_id" ]] && { echo "No gist configured. Run: package-sync sync setup"; exit 1; }

  local tmp; tmp="$(mktemp)"
  gh gist view "$gist_id" --raw > "$tmp"

  # Validate JSON before overwrite
  jq . "$tmp" &>/dev/null || { echo "Remote data invalid JSON. Abort."; rm "$tmp"; exit 1; }

  mv "$tmp" "$PACKAGES_FILE"
  echo "Pulled ← gist:$gist_id"
}

gist_status() {
  _require_gh
  local gist_id; gist_id="$(_get_gist_id)"
  [[ -z "$gist_id" ]] && { echo "No gist configured."; exit 1; }

  local remote_tmp; remote_tmp="$(mktemp)"
  gh gist view "$gist_id" --raw > "$remote_tmp"

  local local_names remote_names
  local_names="$(jq -r '.packages[].name' "$PACKAGES_FILE" | sort)"
  remote_names="$(jq -r '.packages[].name' "$remote_tmp" | sort)"

  echo "=== On remote, not local (run: package-sync sync pull) ==="
  comm -13 <(echo "$local_names") <(echo "$remote_names") | sed 's/^/  + /'

  echo "=== On local, not remote (run: package-sync sync push) ==="
  comm -23 <(echo "$local_names") <(echo "$remote_names") | sed 's/^/  + /'

  rm "$remote_tmp"
}
