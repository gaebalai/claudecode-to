# claudecode.to marketplace — plugin installer for Windows (PowerShell 5.1+)
#
# Copies a plugin's skills from plugins\<name>\skills\* into %USERPROFILE%\.claude\skills\.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
#     (no args)                              # list available plugins
#   powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Plugin harness-edit
#   powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -All
#   powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Plugin <name> -Force
#   powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Plugin <name> -Backup
#   powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Plugin <name> -DryRun
#   powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Plugin <name> -Symlink
#
# Env:
#   CLAUDE_HOME   Override the default %USERPROFILE%\.claude

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Plugin,

    [switch]$All,
    [switch]$Force,
    [switch]$Backup,
    [switch]$DryRun,
    [switch]$Symlink
)

$ErrorActionPreference = 'Stop'

if ($Force -and $Backup) {
    Write-Error "-Force and -Backup are mutually exclusive."
    exit 2
}

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot    = Split-Path -Parent $ScriptDir
$PluginsRoot = Join-Path $RepoRoot 'plugins'

if ($env:CLAUDE_HOME) {
    $Target = Join-Path $env:CLAUDE_HOME 'skills'
} else {
    $Target = Join-Path $env:USERPROFILE '.claude\skills'
}

function Write-Info { param([string]$Msg) Write-Host "→ $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "✓ $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "! $Msg" -ForegroundColor Yellow }

function Invoke-Step {
    param([scriptblock]$Action, [string]$Description)
    if ($DryRun) {
        Write-Host "  [dry-run] $Description" -ForegroundColor DarkGray
    } else {
        & $Action
    }
}

function Show-Plugins {
    Write-Host "Available plugins" -ForegroundColor White
    Write-Host "  (in $PluginsRoot)"
    if (-not (Test-Path -LiteralPath $PluginsRoot -PathType Container)) {
        Write-Error "plugins\ directory not found."
        return
    }
    $found = 0
    Get-ChildItem -LiteralPath $PluginsRoot -Directory | ForEach-Object {
        $name = $_.Name
        $pj   = Join-Path $_.FullName '.claude-plugin\plugin.json'
        $desc = ''
        if (Test-Path -LiteralPath $pj) {
            try {
                $j = Get-Content -LiteralPath $pj -Raw | ConvertFrom-Json
                $desc = $j.description
            } catch { }
        }
        Write-Host ("  {0,-20}  {1}" -f $name, $desc) -ForegroundColor Cyan
        $found++
    }
    if ($found -eq 0) {
        Write-Warn "No plugins found."
    }
    Write-Host ""
    Write-Host "Install with: -Plugin <plugin-name>"
    Write-Host "Install all:  -All"
}

function Install-Skill {
    param([string]$PluginName, [string]$SkillName)

    $src = Join-Path $PluginsRoot "$PluginName\skills\$SkillName"
    $dst = Join-Path $Target $SkillName

    if (-not (Test-Path -LiteralPath $src -PathType Container)) {
        throw "Missing source skill: $src"
    }

    Write-Info "  Installing skill: $SkillName"
    Write-Host "      source: $src"
    Write-Host "      target: $dst"

    if (Test-Path -LiteralPath $dst) {
        if ($Force) {
            Write-Warn "    Existing $dst will be overwritten (-Force)."
            Invoke-Step { Remove-Item -LiteralPath $dst -Recurse -Force } "Remove $dst"
        }
        elseif ($Backup) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $bak   = "$dst.bak.$stamp"
            Write-Warn "    Backing up existing $dst → $bak"
            Invoke-Step { Move-Item -LiteralPath $dst -Destination $bak } "Move to backup"
        }
        else {
            $choice = Read-Host "    Existing $dst detected. [k]eep / [o]verwrite / [b]ackup"
            switch -Regex ($choice) {
                '^(o|O)' {
                    Invoke-Step { Remove-Item -LiteralPath $dst -Recurse -Force } "Remove $dst"
                }
                '^(b|B)' {
                    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $bak   = "$dst.bak.$stamp"
                    Invoke-Step { Move-Item -LiteralPath $dst -Destination $bak } "Move to $bak"
                }
                default {
                    Write-Warn "    Keeping existing $dst — skipped."
                    return
                }
            }
        }
    }

    if ($Symlink) {
        Invoke-Step { New-Item -ItemType SymbolicLink -Path $dst -Target $src | Out-Null } "Symlink $dst → $src"
        Write-Ok "    Linked $SkillName → $src"
    } else {
        Invoke-Step { Copy-Item -LiteralPath $src -Destination $Target -Recurse -Force } "Copy $src → $Target\"
        Write-Ok "    Copied $SkillName"
    }
}

function Install-Plugin {
    param([string]$PluginName)

    $pluginDir = Join-Path $PluginsRoot $PluginName
    if (-not (Test-Path -LiteralPath $pluginDir -PathType Container)) {
        Write-Error "Plugin not found: $PluginName"
        Write-Host "Available plugins:"
        Get-ChildItem -LiteralPath $PluginsRoot -Directory | ForEach-Object {
            Write-Host "    - $($_.Name)"
        }
        return
    }

    Write-Info "Installing plugin: $PluginName"

    $skillsDir = Join-Path $pluginDir 'skills'
    if (-not (Test-Path -LiteralPath $skillsDir -PathType Container)) {
        Write-Warn "  No skills\ directory in $PluginName — nothing to copy."
        return
    }

    Get-ChildItem -LiteralPath $skillsDir -Directory | ForEach-Object {
        Install-Skill -PluginName $PluginName -SkillName $_.Name
    }
}

function Main {
    if (-not $Plugin -and -not $All) {
        Show-Plugins
        return
    }

    Write-Host "claudecode.to installer" -ForegroundColor White
    Write-Host "  target root : $Target"
    if ($DryRun)  { Write-Host "  mode        : dry-run" }
    if ($Force)   { Write-Host "  mode        : force overwrite" }
    if ($Backup)  { Write-Host "  mode        : auto backup" }
    if ($Symlink) { Write-Host "  mode        : symlink (dev) — requires admin or developer mode" }
    Write-Host ""

    if (-not (Test-Path -LiteralPath $PluginsRoot -PathType Container)) {
        throw "plugins\ directory not found: $PluginsRoot"
    }

    Invoke-Step { New-Item -ItemType Directory -Path $Target -Force | Out-Null } "Ensure $Target exists"

    if ($All) {
        Get-ChildItem -LiteralPath $PluginsRoot -Directory | ForEach-Object {
            Install-Plugin -PluginName $_.Name
            Write-Host ""
        }
    } else {
        Install-Plugin -PluginName $Plugin
    }

    Write-Host ""
    Write-Ok "Installation complete."
    Write-Host ""
    Write-Host "Next steps" -ForegroundColor White
    Write-Host "  1. Restart Claude Code, or run /reload-skills in an existing session."
    Write-Host "  2. Invoke the installed skills by their standalone names (e.g. /harness-edit, /ui-style-lab)."
    if ($DryRun) {
        Write-Host ""
        Write-Warn "Dry-run only — nothing was modified."
    }
}

Main
