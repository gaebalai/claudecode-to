#!/usr/bin/env bash
# claudecode.to marketplace — plugin installer for macOS / Linux
#
# Copies a plugin's skills from plugins/<name>/skills/* into ~/.claude/skills/.
# Discovers available plugins from the plugins/ directory.
#
# Usage:
#   ./scripts/install.sh                      # list available plugins
#   ./scripts/install.sh <plugin-name>        # install one plugin
#   ./scripts/install.sh --all                # install every plugin
#   ./scripts/install.sh <name> --force       # overwrite without prompting
#   ./scripts/install.sh <name> --backup      # auto-backup existing dirs
#   ./scripts/install.sh <name> --dry-run     # preview only
#   ./scripts/install.sh <name> --symlink     # symlink (dev mode)
#
# Env:
#   CLAUDE_HOME   override ~/.claude (default: $HOME/.claude)

set -eu

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PLUGINS_ROOT="$SCRIPT_DIR/plugins"
TARGET="${CLAUDE_HOME:-$HOME/.claude}/skills"

FORCE=0
BACKUP=0
DRYRUN=0
SYMLINK=0
ALL=0
PLUGIN=""

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi

log()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
info() { printf '%s→%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }

usage() {
  cat <<EOF
Usage: $0 [PLUGIN] [OPTIONS]

Arguments:
  PLUGIN        Plugin name (e.g. harness-edit, ui-style-lab)
                Omit to list available plugins.

Options:
  --all         Install every plugin in the marketplace
  --force       Overwrite existing skill dirs without prompting
  --backup      Move existing dirs to <name>.bak.YYYYMMDD-HHMMSS before copy
  --dry-run     Print actions only; don't modify the filesystem
  --symlink     Symlink instead of copy (dev mode)
  -h, --help    Show this help

Env:
  CLAUDE_HOME   Override the default ~/.claude root
EOF
}

list_plugins() {
  log "${C_BOLD}Available plugins${C_RESET} (in $PLUGINS_ROOT)"
  if [ ! -d "$PLUGINS_ROOT" ]; then
    err "plugins/ directory not found."
    return 1
  fi
  found=0
  for d in "$PLUGINS_ROOT"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    desc=""
    pj="$d.claude-plugin/plugin.json"
    if [ -f "$pj" ]; then
      desc=$(sed -n 's/.*"description":[[:space:]]*"\([^"]*\)".*/\1/p' "$pj" | head -1)
    fi
    printf '  %s%-20s%s  %s\n' "$C_CYAN" "$name" "$C_RESET" "$desc"
    found=$((found+1))
  done
  if [ $found -eq 0 ]; then
    warn "No plugins found."
  fi
  log ""
  log "Install with: $0 <plugin-name>"
  log "Install all: $0 --all"
}

for arg in "$@"; do
  case "$arg" in
    --all)      ALL=1 ;;
    --force)    FORCE=1 ;;
    --backup)   BACKUP=1 ;;
    --dry-run)  DRYRUN=1 ;;
    --symlink)  SYMLINK=1 ;;
    -h|--help)  usage; exit 0 ;;
    --*)        err "Unknown option: $arg"; usage; exit 2 ;;
    *)
      if [ -z "$PLUGIN" ]; then
        PLUGIN="$arg"
      else
        err "Multiple plugin names given. Use --all to install every plugin."
        exit 2
      fi
      ;;
  esac
done

if [ $FORCE -eq 1 ] && [ $BACKUP -eq 1 ]; then
  err "--force and --backup are mutually exclusive."
  exit 2
fi

if [ -z "$PLUGIN" ] && [ $ALL -eq 0 ]; then
  list_plugins
  exit 0
fi

if [ ! -d "$PLUGINS_ROOT" ]; then
  err "plugins/ directory not found: $PLUGINS_ROOT"
  err "Run this script from the repository checkout."
  exit 1
fi

run() {
  if [ $DRYRUN -eq 1 ]; then
    log "  [dry-run] $*"
  else
    eval "$@"
  fi
}

install_skill() {
  plugin="$1"
  skill="$2"
  src="$PLUGINS_ROOT/$plugin/skills/$skill"
  dst="$TARGET/$skill"

  if [ ! -d "$src" ]; then
    err "Missing source skill: $src"
    return 1
  fi

  info "  Installing skill: ${C_BOLD}$skill${C_RESET}"
  log  "      source: $src"
  log  "      target: $dst"

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ $FORCE -eq 1 ]; then
      warn "    Existing $dst will be overwritten (--force)."
      run "rm -rf \"$dst\""
    elif [ $BACKUP -eq 1 ]; then
      stamp="$(date +%Y%m%d-%H%M%S)"
      bak="$dst.bak.$stamp"
      warn "    Backing up existing $dst → $bak"
      run "mv \"$dst\" \"$bak\""
    else
      printf '    %sExisting%s %s detected. [k]eep / [o]verwrite / [b]ackup ? ' "$C_YELLOW" "$C_RESET" "$dst"
      read -r choice </dev/tty || choice="k"
      case "$choice" in
        o|O|overwrite)
          run "rm -rf \"$dst\""
          ;;
        b|B|backup)
          stamp="$(date +%Y%m%d-%H%M%S)"
          run "mv \"$dst\" \"$dst.bak.$stamp\""
          ;;
        *)
          warn "    Keeping existing $dst — skipped."
          return 0
          ;;
      esac
    fi
  fi

  if [ $SYMLINK -eq 1 ]; then
    run "ln -s \"$src\" \"$dst\""
    ok "    Linked $skill → $src"
  else
    run "cp -R \"$src\" \"$dst\""
    run "chmod -R u+rw \"$dst\""
    ok "    Copied $skill"
  fi
}

install_plugin() {
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

  info "Installing plugin: ${C_BOLD}$plugin${C_RESET}"

  skills_dir="$plugin_dir/skills"
  if [ ! -d "$skills_dir" ]; then
    warn "  No skills/ directory in $plugin — nothing to copy."
    return 0
  fi

  for s in "$skills_dir"/*/; do
    [ -d "$s" ] || continue
    install_skill "$plugin" "$(basename "$s")"
  done
}

main() {
  log "${C_BOLD}claudecode.to installer${C_RESET}"
  log "  target root : $TARGET"
  if [ $DRYRUN  -eq 1 ]; then log "  mode        : dry-run"; fi
  if [ $FORCE   -eq 1 ]; then log "  mode        : force overwrite"; fi
  if [ $BACKUP  -eq 1 ]; then log "  mode        : auto backup"; fi
  if [ $SYMLINK -eq 1 ]; then log "  mode        : symlink (dev)"; fi
  log ""

  run "mkdir -p \"$TARGET\""

  if [ $ALL -eq 1 ]; then
    for d in "$PLUGINS_ROOT"/*/; do
      [ -d "$d" ] || continue
      install_plugin "$(basename "$d")"
      log ""
    done
  else
    install_plugin "$PLUGIN"
  fi

  log ""
  ok "Installation complete."
  log ""
  log "${C_BOLD}Next steps${C_RESET}"
  log "  1. Restart Claude Code, or run /reload-skills in an existing session."
  log "  2. Invoke the installed skills by their standalone names (e.g. /harness-edit, /ui-style-lab)."
  if [ $DRYRUN -eq 1 ]; then
    log ""
    warn "Dry-run only — nothing was modified."
  fi
}

main
