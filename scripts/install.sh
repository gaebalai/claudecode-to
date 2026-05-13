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
SKIP_ENV=0
SKIP_DEPS=0
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
  --skip-env    Skip per-plugin .env / API-key prompts (e.g. blog-shotform-gen)
  --skip-deps   Skip per-plugin runtime dependency checks/installs
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
    --all)        ALL=1 ;;
    --force)      FORCE=1 ;;
    --backup)     BACKUP=1 ;;
    --dry-run)    DRYRUN=1 ;;
    --symlink)    SYMLINK=1 ;;
    --skip-env)   SKIP_ENV=1 ;;
    --skip-deps)  SKIP_DEPS=1 ;;
    -h|--help)    usage; exit 0 ;;
    --*)          err "Unknown option: $arg"; usage; exit 2 ;;
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

  post_install_hook "$plugin"
}

# ─── per-plugin post-install hooks ─────────────────────────────────────────
post_install_hook() {
  plugin="$1"
  case "$plugin" in
    blog-shotform-gen)
      hook_blog_shortform
      ;;
  esac
}

# Checks ffmpeg/ffprobe/python3/node and installs Python deps for blog-url-to-shortform.
ensure_blog_shortform_deps() {
  if [ $SKIP_DEPS -eq 1 ]; then
    info "  Skipping dependency check (--skip-deps)."
    return 0
  fi

  log ""
  info "  ${C_BOLD}Runtime dependency check (blog-url-to-shortform)${C_RESET}"

  missing_cli=""
  for bin in ffmpeg ffprobe python3 node npm; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      missing_cli="$missing_cli $bin"
    fi
  done

  if [ -n "$missing_cli" ]; then
    warn "    Missing CLI tools:$missing_cli"
    if command -v brew >/dev/null 2>&1 && printf '%s' "$missing_cli" | grep -qE 'ffmpeg|ffprobe'; then
      printf "    Install ffmpeg via Homebrew now? [Y/n] "
      if [ -t 0 ]; then
        read -r choice </dev/tty || choice="y"
      else
        choice="n"
      fi
      case "$choice" in
        n|N|no|NO) warn "    Skipped brew install ffmpeg." ;;
        *) run "brew install ffmpeg" ;;
      esac
    else
      warn "    Install them manually:"
      warn "      macOS:  brew install ffmpeg     (also installs ffprobe)"
      warn "              brew install node       (or use nvm; v20 LTS+ required)"
      warn "              brew install python     (Python 3.10+ required)"
      warn "      Linux:  use your package manager (apt / dnf / pacman / etc.)"
    fi
  else
    ok "    ffmpeg / ffprobe / python3 / node / npm — all present."
  fi

  if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import requests, bs4" >/dev/null 2>&1; then
      ok "    Python deps (requests, beautifulsoup4) — present."
    else
      warn "    Python deps missing: requests, beautifulsoup4."
      printf "    Run 'python3 -m pip install --user requests beautifulsoup4' now? [Y/n] "
      if [ -t 0 ]; then
        read -r choice </dev/tty || choice="y"
      else
        choice="n"
      fi
      case "$choice" in
        n|N|no|NO) warn "    Skipped pip install — install manually before first run." ;;
        *) run "python3 -m pip install --user --quiet requests beautifulsoup4 || python3 -m pip install --user --break-system-packages --quiet requests beautifulsoup4" ;;
      esac
    fi
  fi
}

# Walks the user through ELEVENLABS_* / OPENAI_* keys and writes them to
# $TARGET/blog-url-to-shortform/.env. Existing files are preserved unless the
# user chooses to overwrite.
configure_blog_shortform_env() {
  if [ $SKIP_ENV -eq 1 ]; then
    info "  Skipping .env API-key prompt (--skip-env)."
    return 0
  fi

  skill_dir="$TARGET/blog-url-to-shortform"
  env_file="$skill_dir/.env"
  example_file="$skill_dir/.env.example"

  if [ $DRYRUN -eq 1 ]; then
    log "  [dry-run] Would prompt for ELEVENLABS_API_KEY / VOICE_A / VOICE_B / OPENAI_API_KEY"
    log "  [dry-run] Would write to $env_file"
    return 0
  fi

  if [ ! -d "$skill_dir" ]; then
    warn "  Skill directory not present yet ($skill_dir) — skipping .env setup."
    return 0
  fi

  # If $TARGET/blog-url-to-shortform is a symlink (or contains one) pointing
  # inside this repo (e.g. --symlink mode), writing .env there would put
  # secrets under version control. Refuse and let the user choose where.
  resolved_dir=""
  if command -v readlink >/dev/null 2>&1; then
    resolved_dir="$(cd "$skill_dir" 2>/dev/null && pwd -P)"
  fi
  case "$resolved_dir" in
    "$SCRIPT_DIR"*)
      warn "  $skill_dir resolves inside the repo ($resolved_dir)."
      warn "  Refusing to write .env there — secrets must not end up under git."
      warn "  Re-run without --symlink, or set CLAUDE_HOME to a path outside the repo."
      return 0
      ;;
  esac

  log ""
  info "  ${C_BOLD}API key setup → $env_file${C_RESET}"

  if [ -e "$env_file" ]; then
    if [ $FORCE -eq 1 ]; then
      warn "    Existing .env will be overwritten (--force)."
      rm -f "$env_file"
    else
      printf "    %sExisting .env detected.%s [k]eep / [o]verwrite ? " "$C_YELLOW" "$C_RESET"
      if [ -t 0 ]; then
        read -r choice </dev/tty || choice="k"
      else
        choice="k"
      fi
      case "$choice" in
        o|O|overwrite) rm -f "$env_file" ;;
        *) warn "    Keeping existing .env — skipped key prompt."; return 0 ;;
      esac
    fi
  fi

  if [ ! -t 0 ]; then
    warn "    Non-interactive shell — copying .env.example only. Fill keys manually:"
    if [ -f "$example_file" ]; then
      cp "$example_file" "$env_file"
      log  "      $env_file"
    fi
    return 0
  fi

  log "    Press Enter to leave a value blank (you can edit $env_file later)."
  log ""

  prompt_key() {
    # $1 var name, $2 description, $3 default
    var="$1"; desc="$2"; default="$3"
    if [ -n "$default" ]; then
      printf "    %s%s%s [%s]: " "$C_CYAN" "$desc" "$C_RESET" "$default"
    else
      printf "    %s%s%s: " "$C_CYAN" "$desc" "$C_RESET"
    fi
    read -r value </dev/tty || value=""
    if [ -z "$value" ] && [ -n "$default" ]; then
      value="$default"
    fi
    # Assign $value to the variable named by $var via single expansion of $value
    # (no embedded quoting, so backslash/$/` in the input stay literal).
    eval "$var=\$value"
  }

  prompt_key ELEVENLABS_API_KEY "ELEVENLABS_API_KEY (https://elevenlabs.io/app/settings/api-keys)" ""
  prompt_key ELEVENLABS_VOICE_A "ELEVENLABS_VOICE_A   (e.g. Rosa Oh, 한국어 여성 voice id)" ""
  prompt_key ELEVENLABS_VOICE_B "ELEVENLABS_VOICE_B   (e.g. Joon Park, 한국어 남성 voice id)" ""
  prompt_key ELEVENLABS_MODEL   "ELEVENLABS_MODEL     (TTS model; Enter = default)"            "eleven_multilingual_v2"
  prompt_key OPENAI_API_KEY     "OPENAI_API_KEY       (https://platform.openai.com/api-keys)"  ""
  prompt_key OPENAI_IMAGE_MODEL "OPENAI_IMAGE_MODEL   (Enter = default)"                       "gpt-image-2"
  prompt_key OPENAI_IMAGE_SIZE  "OPENAI_IMAGE_SIZE    (Enter = default)"                       "1024x1536"

  umask_old=$(umask)
  umask 077
  {
    printf '%s\n' "# blog-url-to-shortform — generated by install.sh on $(date +%Y-%m-%dT%H:%M:%S)"
    printf '%s\n' "# Do NOT commit this file."
    printf '\n'
    printf 'ELEVENLABS_API_KEY=%s\n' "$ELEVENLABS_API_KEY"
    printf 'ELEVENLABS_VOICE_A=%s\n' "$ELEVENLABS_VOICE_A"
    printf 'ELEVENLABS_VOICE_B=%s\n' "$ELEVENLABS_VOICE_B"
    printf 'ELEVENLABS_MODEL=%s\n'   "$ELEVENLABS_MODEL"
    printf '\n'
    printf 'OPENAI_API_KEY=%s\n'     "$OPENAI_API_KEY"
    printf 'OPENAI_IMAGE_MODEL=%s\n' "$OPENAI_IMAGE_MODEL"
    printf 'OPENAI_IMAGE_SIZE=%s\n'  "$OPENAI_IMAGE_SIZE"
  } > "$env_file"
  chmod 600 "$env_file" 2>/dev/null || true
  umask "$umask_old"

  ok "    Wrote $env_file (chmod 600)."
  log "    You can edit it later if a key was left blank."
}

hook_blog_shortform() {
  ensure_blog_shortform_deps
  configure_blog_shortform_env
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
  log "  2. Invoke the installed skills by their standalone names"
  log "     (e.g. /harness-edit, /ui-style-lab, /blog-url-to-shortform)."
  if [ $DRYRUN -eq 1 ]; then
    log ""
    warn "Dry-run only — nothing was modified."
  fi
}

main
