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
#   powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Plugin blog-shotform-gen -SkipEnv -SkipDeps
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
    [switch]$Symlink,
    [switch]$SkipEnv,
    [switch]$SkipDeps
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

    Invoke-PostInstallHook -PluginName $PluginName
}

# ─── per-plugin post-install hooks ─────────────────────────────────────────
function Invoke-PostInstallHook {
    param([string]$PluginName)
    switch ($PluginName) {
        'blog-shotform-gen' { Invoke-BlogShortformHook }
    }
}

function Test-BlogShortformDeps {
    if ($SkipDeps) {
        Write-Info "  Skipping dependency check (-SkipDeps)."
        return
    }

    Write-Host ""
    Write-Info "  Runtime dependency check (blog-url-to-shortform)"

    $required = @('ffmpeg','ffprobe','python','node','npm')
    $missing  = @()
    foreach ($cli in $required) {
        if (-not (Get-Command $cli -ErrorAction SilentlyContinue)) {
            # python may be installed as python3 on some setups
            if ($cli -eq 'python' -and (Get-Command 'python3' -ErrorAction SilentlyContinue)) { continue }
            $missing += $cli
        }
    }

    if ($missing.Count -gt 0) {
        Write-Warn ("    Missing CLI tools: " + ($missing -join ', '))
        Write-Warn "    Install them manually before first run:"
        Write-Warn "      ffmpeg + ffprobe : https://www.gyan.dev/ffmpeg/builds/  (or 'winget install ffmpeg')"
        Write-Warn "      Node.js v20 LTS+ : https://nodejs.org/  (or 'winget install OpenJS.NodeJS.LTS')"
        Write-Warn "      Python 3.10+     : https://python.org   (or 'winget install Python.Python.3.12')"
    } else {
        Write-Ok "    ffmpeg / ffprobe / python / node / npm — all present."
    }

    $pythonBin = (Get-Command 'python' -ErrorAction SilentlyContinue)
    if (-not $pythonBin) { $pythonBin = (Get-Command 'python3' -ErrorAction SilentlyContinue) }

    if ($pythonBin) {
        $hasDeps = $false
        try {
            & $pythonBin.Source -c 'import requests, bs4' 2>$null
            if ($LASTEXITCODE -eq 0) { $hasDeps = $true }
        } catch { }

        if ($hasDeps) {
            Write-Ok "    Python deps (requests, beautifulsoup4) — present."
        } else {
            Write-Warn "    Python deps missing: requests, beautifulsoup4."
            $choice = Read-Host "    Run 'pip install --user requests beautifulsoup4' now? [Y/n]"
            if ($choice -notmatch '^(n|N)') {
                if ($DryRun) {
                    Write-Host "  [dry-run] $($pythonBin.Source) -m pip install --user requests beautifulsoup4" -ForegroundColor DarkGray
                } else {
                    & $pythonBin.Source -m pip install --user --quiet requests beautifulsoup4
                }
            } else {
                Write-Warn "    Skipped pip install — install manually before first run."
            }
        }
    }
}

function Set-BlogShortformEnv {
    if ($SkipEnv) {
        Write-Info "  Skipping .env API-key prompt (-SkipEnv)."
        return
    }

    $skillDir    = Join-Path $Target 'blog-url-to-shortform'
    $envFile     = Join-Path $skillDir '.env'
    $exampleFile = Join-Path $skillDir '.env.example'

    if ($DryRun) {
        Write-Host "  [dry-run] Would prompt for ELEVENLABS_API_KEY / VOICE_A / VOICE_B / OPENAI_API_KEY" -ForegroundColor DarkGray
        Write-Host "  [dry-run] Would write to $envFile" -ForegroundColor DarkGray
        return
    }

    if (-not (Test-Path -LiteralPath $skillDir -PathType Container)) {
        Write-Warn "  Skill directory not present yet ($skillDir) — skipping .env setup."
        return
    }

    # If the skill dir resolves inside this repo (e.g. -Symlink mode), do not
    # write .env there — secrets must not end up under version control.
    try {
        $resolved = (Resolve-Path -LiteralPath $skillDir).ProviderPath
        if ($resolved.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Warn "  $skillDir resolves inside the repo ($resolved)."
            Write-Warn "  Refusing to write .env there — secrets must not end up under git."
            Write-Warn "  Re-run without -Symlink, or set CLAUDE_HOME to a path outside the repo."
            return
        }
    } catch { }

    Write-Host ""
    Write-Info "  API key setup → $envFile"

    if (Test-Path -LiteralPath $envFile) {
        if ($Force) {
            Write-Warn "    Existing .env will be overwritten (-Force)."
            Remove-Item -LiteralPath $envFile -Force
        } else {
            $choice = Read-Host "    Existing .env detected. [k]eep / [o]verwrite"
            if ($choice -match '^(o|O)') {
                Remove-Item -LiteralPath $envFile -Force
            } else {
                Write-Warn "    Keeping existing .env — skipped key prompt."
                return
            }
        }
    }

    Write-Host "    Press Enter to leave a value blank (you can edit $envFile later)."
    Write-Host ""

    function _PromptKey {
        param([string]$Description, [string]$Default)
        if ($Default) {
            $label = "    $Description [$Default]"
        } else {
            $label = "    $Description"
        }
        $value = Read-Host $label
        if (-not $value -and $Default) { return $Default }
        return $value
    }

    $elevenKey   = _PromptKey "ELEVENLABS_API_KEY (https://elevenlabs.io/app/settings/api-keys)" ""
    $voiceA      = _PromptKey "ELEVENLABS_VOICE_A   (e.g. Rosa Oh, 한국어 여성 voice id)"      ""
    $voiceB      = _PromptKey "ELEVENLABS_VOICE_B   (e.g. Joon Park, 한국어 남성 voice id)"     ""
    $elevenModel = _PromptKey "ELEVENLABS_MODEL     (Enter = default)"                          "eleven_multilingual_v2"
    $openaiKey   = _PromptKey "OPENAI_API_KEY       (https://platform.openai.com/api-keys)"    ""
    $imgModel    = _PromptKey "OPENAI_IMAGE_MODEL   (Enter = default)"                          "gpt-image-2"
    $imgSize     = _PromptKey "OPENAI_IMAGE_SIZE    (Enter = default)"                          "1024x1536"

    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
    $contents = @"
# blog-url-to-shortform — generated by install.ps1 on $timestamp
# Do NOT commit this file.

ELEVENLABS_API_KEY=$elevenKey
ELEVENLABS_VOICE_A=$voiceA
ELEVENLABS_VOICE_B=$voiceB
ELEVENLABS_MODEL=$elevenModel

OPENAI_API_KEY=$openaiKey
OPENAI_IMAGE_MODEL=$imgModel
OPENAI_IMAGE_SIZE=$imgSize
"@
    Set-Content -LiteralPath $envFile -Value $contents -Encoding UTF8

    Write-Ok "    Wrote $envFile."
    Write-Host "    You can edit it later if a key was left blank."
}

function Invoke-BlogShortformHook {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','')]
    param()
    Test-BlogShortformDeps
    Set-BlogShortformEnv
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
    Write-Host "  2. Invoke the installed skills by their standalone names"
    Write-Host "     (e.g. /harness-edit, /ui-style-lab, /blog-url-to-shortform)."
    if ($DryRun) {
        Write-Host ""
        Write-Warn "Dry-run only — nothing was modified."
    }
}

Main
