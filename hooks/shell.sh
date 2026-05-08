#!/usr/bin/env bash
# package-sync shell hook — detects install commands and prompts to track

# Check remote for new packages on terminal open
_PKGSYNC_NOTIFY="${PKGSYNC_DIR:-$HOME/.package-sync}/hooks/notify.sh"
[[ -f "$_PKGSYNC_NOTIFY" ]] && source "$_PKGSYNC_NOTIFY"

_PKGSYNC_BIN="${PKGSYNC_BIN:-$HOME/.package-sync/bin/package-sync}"
_PKGSYNC_LAST_CMD=""

# Patterns that signal a package install
_pkgsync_is_install_cmd() {
  local cmd="$1"
  echo "$cmd" | grep -qE \
    '^(brew install|pip install|pip3 install|npm install -g|npm i -g|cargo install|apt install|apt-get install|winget install|gem install|go install)' \
    && return 0
  # curl/wget piped to bash (like cursor example)
  echo "$cmd" | grep -qE '(curl|wget).*(bash|sh)' && return 0
  return 1
}

# Extract package name from install command (BSD grep compatible)
_pkgsync_extract_name() {
  local cmd="$1"
  local name=""

  case "$cmd" in
    brew\ install\ --cask\ *|brew\ install\ -s\ *)
      name="$(echo "$cmd" | sed 's/brew install \(--cask\|-s\) *//' | awk '{print $1}')"
      ;;
    brew\ install\ *)
      name="$(echo "$cmd" | sed 's/brew install *//' | awk '{print $1}')"
      ;;
    pip3\ install\ *|pip\ install\ *)
      name="$(echo "$cmd" | sed 's/pip3\{0,1\} install *//' | tr ' ' '\n' | grep -v '^-' | head -1)"
      ;;
    npm\ install\ -g\ *|npm\ i\ -g\ *)
      name="$(echo "$cmd" | sed 's/npm \(install\|i\) -g *//' | awk '{print $1}')"
      ;;
    cargo\ install\ *)
      name="$(echo "$cmd" | sed 's/cargo install *//' | tr ' ' '\n' | grep -v '^-' | head -1)"
      ;;
    apt-get\ install\ *|apt\ install\ *)
      name="$(echo "$cmd" | sed 's/apt-get install\|apt install//' | tr ' ' '\n' | grep -v '^-' | head -1)"
      ;;
    winget\ install\ *)
      name="$(echo "$cmd" | sed 's/winget install *//' | awk '{print $1}')"
      ;;
    gem\ install\ *)
      name="$(echo "$cmd" | sed 's/gem install *//' | awk '{print $1}')"
      ;;
  esac

  echo "${name// /}"
}

_pkgsync_extract_manager() {
  local cmd="$1"
  case "$cmd" in
    brew*)   echo "brew" ;;
    pip3*)   echo "pip" ;;
    pip*)    echo "pip" ;;
    npm*)    echo "npm" ;;
    cargo*)  echo "cargo" ;;
    apt*)    echo "apt" ;;
    winget*) echo "winget" ;;
    gem*)    echo "gem" ;;
    curl*|wget*) echo "custom" ;;
    *)       echo "unknown" ;;
  esac
}

_pkgsync_extract_curl_url() {
  local cmd="$1"
  echo "$cmd" | grep -oE 'https?://[^ |]+' | head -1
}

_pkgsync_run_add() {
  local name="$1" manager="$2" url="${3:-}"
  if command -v package-sync &>/dev/null; then
    package-sync add "$name" "$manager" "$url"
  elif [[ -x "$_PKGSYNC_BIN" ]]; then
    "$_PKGSYNC_BIN" add "$name" "$manager" "$url"
  else
    echo "package-sync not found in PATH. Run manually."
  fi
}

_pkgsync_prompt() {
  local cmd="$1"
  local manager; manager="$(_pkgsync_extract_manager "$cmd")"

  # curl/wget — special flow: ask for name + capture URL
  if [[ "$manager" == "custom" ]]; then
    local url; url="$(_pkgsync_extract_curl_url "$cmd")"
    echo ""
    echo "📦 package-sync: Detected curl install."
    [[ -n "$url" ]] && echo "   URL: $url"
    read -r -p "   What's the name of what you installed? (empty to skip): " name
    [[ -z "$name" ]] && return
    _pkgsync_run_add "$name" "curl" "$url"
    return
  fi

  local name; name="$(_pkgsync_extract_name "$cmd")"
  [[ -z "$name" ]] && return

  echo ""
  echo "📦 package-sync: Add '$name' to your backup?"
  read -r -p "   Add now? [y/N] " choice
  case "$choice" in
    [yY]*) _pkgsync_run_add "$name" "$manager" ;;
  esac
}

# ZSH hooks
if [[ -n "${ZSH_VERSION:-}" ]]; then
  autoload -Uz add-zsh-hook 2>/dev/null || true

  _pkgsync_preexec() {
    _PKGSYNC_LAST_CMD="$1"
  }

  _pkgsync_precmd() {
    local cmd="$_PKGSYNC_LAST_CMD"
    _PKGSYNC_LAST_CMD=""
    [[ -z "$cmd" ]] && return
    _pkgsync_is_install_cmd "$cmd" && _pkgsync_prompt "$cmd"
  }

  add-zsh-hook preexec _pkgsync_preexec
  add-zsh-hook precmd _pkgsync_precmd

# BASH hooks
elif [[ -n "${BASH_VERSION:-}" ]]; then
  _pkgsync_bash_prompt() {
    local exit_code=$?
    local cmd
    cmd="$(history 1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')"
    if [[ "$cmd" != "$_PKGSYNC_LAST_CMD" ]]; then
      _PKGSYNC_LAST_CMD="$cmd"
      _pkgsync_is_install_cmd "$cmd" && _pkgsync_prompt "$cmd"
    fi
    return $exit_code
  }

  PROMPT_COMMAND="_pkgsync_bash_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi
