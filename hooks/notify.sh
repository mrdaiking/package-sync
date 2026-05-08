#!/usr/bin/env bash
# Fires on terminal open — checks remote gist for new packages

_pkgsync_check_remote() {
  local config="$HOME/.package-sync/config.json"
  local packages="$HOME/.package-sync/packages.json"

  [[ -f "$config" ]] || return 0
  [[ -f "$packages" ]] || return 0

  local gist_id
  gist_id="$(jq -r '.gist_id // empty' "$config" 2>/dev/null)"
  [[ -z "$gist_id" ]] && return 0

  command -v gh &>/dev/null || return 0
  gh auth status &>/dev/null 2>&1 || return 0

  local remote_tmp; remote_tmp="$(mktemp)"
  gh gist view "$gist_id" --raw > "$remote_tmp" 2>/dev/null || { rm "$remote_tmp"; return 0; }

  # Find packages on remote not in local
  local new_packages
  new_packages="$(comm -13 \
    <(jq -r '.packages[].name' "$packages" 2>/dev/null | sort) \
    <(jq -r '.packages[].name' "$remote_tmp" 2>/dev/null | sort))"

  if [[ -n "$new_packages" ]]; then
    local count; count="$(echo "$new_packages" | wc -l | tr -d ' ')"
    echo ""
    echo "📦 package-sync: $count new package(s) on remote:"
    while IFS= read -r pkg; do
      local info
      info="$(jq -r --arg n "$pkg" \
        '.packages[] | select(.name==$n) | "  + \(.name) (\(.manager)) — from \(.device)"' \
        "$remote_tmp" 2>/dev/null)"
      echo "$info"
    done <<< "$new_packages"
    echo "   Run: package-sync sync pull"
    echo ""
  fi

  rm "$remote_tmp"
}

# Only run if interactive shell
[[ $- == *i* ]] && _pkgsync_check_remote
