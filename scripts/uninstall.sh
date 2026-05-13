#!/usr/bin/env bash
# claudecode.to marketplace — plugin uninstaller for macOS / Linux
#
# Removes a plugin's skills from ~/.claude/skills/.
# Backups (*.bak.*) are preserved.
#
# Usage:
#   ./scripts/uninstall.sh                    # list plugins available to remove
#   ./scripts/uninstall.sh <plugin-name>      # remove one plugin's skills (with prompt)
#   ./scripts/uninstall.sh --all              # remove every plugin's skills
#   ./scripts/uninstall.sh <name> --yes       # no prompt
#
# Env:
#   CLAUDE_HOME   override ~/.claude (default: $HOME/.claude)

set -eu

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PLUGINS_ROOT="$SCRIPT_DIR/plugins"
TARGET="${CLAUDE_HOME:-$HOME/.claude}/skills"

YES=0
ALL=0
PLUGIN=""

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi

ok()   { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
info() { printf '%s→%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }

usage() {
  cat <<EOF
Usage: $0 [PLUGIN] [--yes] [--all]

Removes a plugin's skills from $TARGET (or \$CLAUDE_HOME/skills).
Backups (*.bak.*) are preserved.

Arguments:
  PLUGIN   Plugin name (omit to list available plugins)
  --all    Remove every plugin's skills
  --yes    Skip confirmation prompts
EOF
}

list_plugins() {
  log_local() { printf '%s\n' "$*"; }
  log_local "${C_BOLD}Available plugins${C_RESET} (in $PLUGINS_ROOT)"
  if [ ! -d "$PLUGINS_ROOT" ]; then
    err "plugins/ directory not found."
    return 1
  fi
  for d in "$PLUGINS_ROOT"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    printf '  %s%s%s\n' "$C_CYAN" "$name" "$C_RESET"
  done
  log_local ""
  log_local "Uninstall with: $0 <plugin-name>"
}

for arg in "$@"; do
  case "$arg" in
    --yes|-y)  YES=1 ;;
    --all)     ALL=1 ;;
    -h|--help) usage; exit 0 ;;
    --*)       err "Unknown option: $arg"; exit 2 ;;
    *)
      if [ -z "$PLUGIN" ]; then
        PLUGIN="$arg"
      else
        err "Multiple plugin names given. Use --all to remove all."
        exit 2
      fi
      ;;
  esac
done

if [ -z "$PLUGIN" ] && [ $ALL -eq 0 ]; then
  list_plugins
  exit 0
fi

remove_skill() {
  skill="$1"
  dst="$TARGET/$skill"

  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    warn "Not installed: $dst"
    return 0
  fi

  if [ $YES -eq 0 ]; then
    printf "Remove %s ? [y/N] " "$dst"
    read -r choice </dev/tty || choice="n"
    case "$choice" in
      y|Y|yes|YES) ;;
      *) warn "Skipped $skill."; return 0 ;;
    esac
  fi

  # Preserve any .env (API keys) before nuking the skill directory.
  env_file="$dst/.env"
  if [ -f "$env_file" ]; then
    stamp="$(date +%Y%m%d-%H%M%S)"
    bak="$dst.env.bak.$stamp"
    if cp "$env_file" "$bak" 2>/dev/null; then
      chmod 600 "$bak" 2>/dev/null || true
      info "  Backed up .env → $bak"
    else
      warn "  Failed to back up $env_file — aborting remove to protect secrets."
      return 1
    fi
  fi

  rm -rf "$dst"
  ok "Removed $skill."
}

remove_plugin() {
  plugin="$1"
  plugin_dir="$PLUGINS_ROOT/$plugin"

  if [ ! -d "$plugin_dir" ]; then
    err "Plugin not found: $plugin"
    err "Available plugins:"
    for d in "$PLUGINS_ROOT"/*/; do
      [ -d "$d" ] && printf '    - %s\n' "$(basename "$d")"
    done
    return 1
  fi

  info "Uninstalling plugin: ${C_BOLD}$plugin${C_RESET}"

  skills_dir="$plugin_dir/skills"
  if [ ! -d "$skills_dir" ]; then
    warn "  No skills/ directory in $plugin — nothing to remove."
    return 0
  fi

  for s in "$skills_dir"/*/; do
    [ -d "$s" ] || continue
    remove_skill "$(basename "$s")"
  done
}

info "Target: $TARGET"

if [ $ALL -eq 1 ]; then
  for d in "$PLUGINS_ROOT"/*/; do
    [ -d "$d" ] || continue
    remove_plugin "$(basename "$d")"
  done
else
  remove_plugin "$PLUGIN"
fi

echo
ok "Done."
echo "Restart Claude Code or run /reload-skills to refresh."
