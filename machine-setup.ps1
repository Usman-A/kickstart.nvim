#Requires -Version 5.1
<#
.SYNOPSIS
    machine-setup.ps1 - Windows counterpart to machine-setup.sh

.DESCRIPTION
    Run once on a new Windows machine after cloning your Neovim config.
    Installs the system-level dependencies that vim.pack and Mason cannot manage.

    TWO INSTALL PATHS, selected with -Mode:

      -Mode User    No administrator rights required. winget --scope user plus
                    portable ZIPs for the packages whose MSIs insist on
                    installing machine-wide. Everything lands in your own
                    profile. This is the path to use on a managed corporate
                    machine where you only have policy-scoped elevation
                    (e.g. Microsoft Intune Endpoint Privilege Management,
                    "Run with elevated access") rather than real UAC admin.

      -Mode Admin   The conventional path: official machine-wide MSIs via
                    winget default scope, into C:\Program Files and the
                    machine PATH. Needs a genuinely elevated shell. Also
                    installs the .NET SDK, which User mode cannot.

      -Mode Auto    (default) Admin if this shell is already elevated,
                    otherwise User.

    In User mode everything installs into your own user profile:

      winget --scope user  -> %LOCALAPPDATA%\Microsoft\WinGet\Packages
      portable zips        -> %LOCALAPPDATA%\Programs
      npm globals          -> %APPDATA%\npm

    Node, Go and the JDK are published as MSIs that insist on machine-wide
    install (they fail with exit 1602 when UAC is declined), so this script
    installs those three from their official ZIP distributions instead and
    wires them into your USER PATH. Same binaries, no elevation.

    The machine PATH is never modified.

.PARAMETER SkipLatex
    Skip MiKTeX + SumatraPDF. MiKTeX is a large install.

.PARAMETER SkipJava
    Skip the Temurin JDK (needed by the jdtls LSP).

.PARAMETER SkipDotnet
    Skip the .NET SDK check (needed by the omnisharp LSP).

.PARAMETER SkipGo
    Skip Go (needed by the gopls LSP).

.PARAMETER SkipRust
    Skip rustup. Rust is only needed for the rust_analyzer LSP;
    tree-sitter is installed via npm regardless.

.EXAMPLE
    .\machine-setup.ps1
    Install everything, no elevation needed.

.EXAMPLE
    .\machine-setup.ps1 -SkipLatex -SkipJava
    Install everything except MiKTeX and the JDK.

.NOTES
    The .NET SDK is the one dependency this script cannot install without
    admin. It is usually already present on a corporate image; the script
    checks and tells you rather than failing. omnisharp is the only thing
    that needs it.

    Treesitter parser compilation needs a C compiler. WinLibs provides gcc,
    but the tree-sitter CLI looks for `cc` or MSVC `cl`. init.lua handles
    that by setting vim.env.CC = 'gcc' on Windows, so no shim is needed here.
#>
[CmdletBinding()]
param(
    # Auto  - pick Admin if this shell is elevated, otherwise User (default)
    # User  - never require elevation: winget --scope user + portable zips
    # Admin - prefer the official machine-wide MSIs; needs a real UAC admin
    [ValidateSet('Auto', 'User', 'Admin')]
    [string]$Mode = 'Auto',

    [switch]$SkipLatex,
    [switch]$SkipJava,
    [switch]$SkipDotnet,
    [switch]$SkipGo,
    [switch]$SkipRust
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Failures = @()
$script:ProgramsDir = Join-Path $env:LOCALAPPDATA 'Programs'

# -------------------------------------------------------------
# Logging
# -------------------------------------------------------------
function Write-Section { param([string]$Message) Write-Host "`n>> $Message" -ForegroundColor Blue }
function Write-Ok      { param([string]$Message) Write-Host "  [ok]   $Message" -ForegroundColor Green }
function Write-Skip    { param([string]$Message) Write-Host "  [skip] $Message" -ForegroundColor Yellow }
function Write-Warn    { param([string]$Message) Write-Host "  [warn] $Message" -ForegroundColor Yellow }
function Write-Fail    { param([string]$Message) Write-Host "  [fail] $Message" -ForegroundColor Red }
function Write-Step    { param([string]$Message) Write-Host "  ...    $Message" }

# -------------------------------------------------------------
# Environment helpers
# -------------------------------------------------------------

# Installers write PATH to the registry, not to this process. Without
# re-reading it, every "is X installed" check after an install still fails.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

# Append to the USER PATH only, and only if absent. Never touches Machine.
function Add-UserPath {
    param([Parameter(Mandatory)][string]$Directory)

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($userPath) { $parts = ($userPath -split ';') | Where-Object { $_ } }

    if ($parts -contains $Directory) {
        Write-Skip "already on user PATH: $Directory"
    } else {
        $parts += $Directory
        [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
        Write-Ok "added to user PATH: $Directory"
    }
    Update-SessionPath
}

function Test-CommandExists {
    param([string]$Name)
    [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-VersionLine {
    param([string]$Exe, [string[]]$Arguments = @('--version'))
    try {
        $out = & $Exe @Arguments 2>&1 | Select-Object -First 1
        if ($out) { return ($out | Out-String).Trim() }
    } catch { }
    return 'installed'
}

# -------------------------------------------------------------
# winget wrapper - user scope first
# -------------------------------------------------------------
# Exit codes worth special-casing:
#   0            success
#   -1978335189  already installed / no applicable upgrade
#   -1978335216  installer does not support the requested scope
#   -1978334964  installer failed (wraps MSI 1602 = UAC declined)
#   1602         installer cancelled (dismissed UAC prompt)
function Install-WingetPackage {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label,
        [string]$ProbeCommand
    )

    if ($ProbeCommand -and (Test-CommandExists $ProbeCommand)) {
        Write-Skip "$Label ($(Get-VersionLine $ProbeCommand))"
        return $true
    }

    $common = @(
        'install', '--id', $Id, '--exact', '--source', 'winget',
        '--accept-source-agreements', '--accept-package-agreements',
        '--disable-interactivity'
    )

    Write-Step "installing $Label ($Id)"

    $userCode = 'n/a'
    if ($script:EffectiveMode -eq 'User') {
        # Prefer an explicit user-scope install: no elevation, lands in this
        # profile. Admin mode skips this and goes straight to machine scope,
        # which is what you actually want when you do have rights.
        & winget @common --scope user *> $null
        $userCode = $LASTEXITCODE
        if ($userCode -eq 0) { Update-SessionPath; Write-Ok "$Label installed (user scope)"; return $true }
        if ($userCode -eq -1978335189) { Write-Skip "$Label (already installed)"; return $true }
    }

    # Fall back to the package's default scope. Portable/zip packages still
    # land per-user; MSIs will ask for UAC and fail if it is declined.
    & winget @common *> $null
    $code = $LASTEXITCODE
    switch ($code) {
        0 { Update-SessionPath; Write-Ok "$Label installed"; return $true }
        -1978335189 { Write-Skip "$Label (already installed)"; return $true }
        default {
            if ($code -eq 1602 -or $code -eq -1978334964) {
                Write-Fail "$Label - installer needs administrator (UAC declined)"
                $script:Failures += "$Label (needs admin; winget $code)"
            } else {
                Write-Fail "$Label - winget exit $code (user-scope attempt: $userCode)"
                $script:Failures += "$Label (winget $code)"
            }
            return $false
        }
    }
}

# -------------------------------------------------------------
# Portable-zip installer
# -------------------------------------------------------------
# Used for the three packages whose MSIs demand machine-wide install.
# Extracts into %LOCALAPPDATA%\Programs and returns the final directory.
function Install-FromZip {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$FinalName,   # dir name under Programs
        [string]$RootPattern                         # zip's top-level dir, if it needs renaming
    )

    New-Item -ItemType Directory -Force -Path $script:ProgramsDir | Out-Null
    $final = Join-Path $script:ProgramsDir $FinalName

    $zip = Join-Path $env:TEMP ("$FinalName.zip")
    Write-Step "downloading $Label"
    Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing -MaximumRedirection 5
    Write-Step ("downloaded {0:N1} MB" -f ((Get-Item $zip).Length / 1MB))

    if (Test-Path $final) { Remove-Item -Recurse -Force $final }

    # 7-Zip is dramatically faster than Expand-Archive on these (Go and the
    # JDK are tens of thousands of small files). Fall back if absent.
    $sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
    Write-Step "extracting $Label"
    if (Test-Path $sevenZip) {
        & $sevenZip x $zip "-o$script:ProgramsDir" -y -bso0 -bsp0
        if ($LASTEXITCODE -ne 0) { throw "7z failed with exit $LASTEXITCODE" }
    } else {
        Expand-Archive -Path $zip -DestinationPath $script:ProgramsDir -Force
    }

    # Most of these zips contain a single versioned top-level directory.
    if ($RootPattern) {
        $root = Get-ChildItem $script:ProgramsDir -Directory |
                Where-Object { $_.Name -like $RootPattern } |
                Select-Object -First 1
        if ($root -and $root.FullName -ne $final) {
            Rename-Item -Path $root.FullName -NewName $FinalName
        }
    }

    if (-not (Test-Path $final)) { throw "expected $final after extracting $Label" }
    Write-Ok "$Label -> $final"
    return $final
}

# -------------------------------------------------------------
# Base build tools
# -------------------------------------------------------------
# WinLibs provides gcc, which nvim-treesitter needs to compile parsers.
# CMake is the fallback build path for telescope-fzf-native when make is
# absent; make covers the default path. All install user-scope.
function Install-BaseTools {
    Write-Section 'Base build tools (git, gcc, make, cmake, 7zip, fd, ripgrep)'

    # 7zip first: Install-FromZip uses it later if present.
    Install-WingetPackage -Id '7zip.7zip'                        -Label '7zip'    -ProbeCommand '7z'    | Out-Null
    Install-WingetPackage -Id 'Git.Git'                          -Label 'git'     -ProbeCommand 'git'   | Out-Null
    Install-WingetPackage -Id 'BrechtSanders.WinLibs.POSIX.UCRT' -Label 'gcc'     -ProbeCommand 'gcc'   | Out-Null
    Install-WingetPackage -Id 'ezwinports.make'                  -Label 'make'    -ProbeCommand 'make'  | Out-Null
    Install-WingetPackage -Id 'Kitware.CMake'                    -Label 'cmake'   -ProbeCommand 'cmake' | Out-Null
    Install-WingetPackage -Id 'sharkdp.fd'                       -Label 'fd'      -ProbeCommand 'fd'    | Out-Null
    Install-WingetPackage -Id 'BurntSushi.ripgrep.MSVC'          -Label 'ripgrep' -ProbeCommand 'rg'    | Out-Null
}

# -------------------------------------------------------------
# Neovim
# -------------------------------------------------------------
function Install-Neovim {
    Write-Section 'Neovim'
    Install-WingetPackage -Id 'Neovim.Neovim' -Label 'neovim' -ProbeCommand 'nvim' | Out-Null

    if (-not (Test-CommandExists 'nvim')) {
        foreach ($dir in @((Join-Path $env:ProgramFiles 'Neovim\bin'),
                           (Join-Path $env:LOCALAPPDATA 'Programs\Neovim\bin'))) {
            if (Test-Path (Join-Path $dir 'nvim.exe')) {
                Write-Warn "nvim.exe is at $dir but not on PATH - open a new shell."
                break
            }
        }
    }
}

# -------------------------------------------------------------
# win32yank - clipboard bridge for WSL
# -------------------------------------------------------------
# Native Windows Neovim needs no clipboard helper. This is installed on the
# Windows side so Neovim running *inside WSL* can reach the Windows clipboard:
# WSL inherits the Windows PATH, so win32yank.exe becomes callable from the
# Linux side. init.lua picks it up automatically when is_wsl is true.
function Install-Win32Yank {
    Write-Section 'win32yank (clipboard bridge for WSL)'
    Install-WingetPackage -Id 'equalsraf.win32yank' -Label 'win32yank' -ProbeCommand 'win32yank' | Out-Null
}

# -------------------------------------------------------------
# Node.js (zip) + npm packages
# -------------------------------------------------------------
# The official Node MSI installs machine-wide and needs UAC. The zip does not.
function Install-Node {
    if ($script:EffectiveMode -eq 'Admin') {
        Write-Section 'Node.js (LTS, machine-wide MSI)'
        Install-WingetPackage -Id 'OpenJS.NodeJS.LTS' -Label 'node' -ProbeCommand 'node' | Out-Null
        # npm's global bin is per-user even with a machine-wide Node.
        Add-UserPath (Join-Path $env:APPDATA 'npm')
        return
    }

    Write-Section 'Node.js (LTS, portable zip)'

    if (Test-CommandExists 'node') {
        Write-Skip "node ($(Get-VersionLine 'node'))"
    } else {
        try {
            $index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
            $lts = $index | Where-Object { $_.lts } | Select-Object -First 1
            $ver = $lts.version
            Write-Step "latest LTS is $ver ($($lts.lts))"
            $dir = Install-FromZip `
                -Url "https://nodejs.org/dist/$ver/node-$ver-win-x64.zip" `
                -Label "node $ver" -FinalName 'nodejs' -RootPattern "node-$ver-win-x64"
            Add-UserPath $dir
            # npm's global bin lives here and must also be on PATH.
            Add-UserPath (Join-Path $env:APPDATA 'npm')
        } catch {
            Write-Fail "node - $($_.Exception.Message)"
            $script:Failures += 'node'
            return
        }
    }
    if (-not (Test-Path (Join-Path $env:APPDATA 'npm'))) {
        New-Item -ItemType Directory -Force -Path (Join-Path $env:APPDATA 'npm') | Out-Null
    }
}

function Install-NpmPackages {
    Write-Section 'npm global packages'

    if (-not (Test-CommandExists 'npm')) {
        Write-Warn 'npm not found - skipping. Open a new shell and re-run.'
        $script:Failures += 'npm packages (npm not on PATH yet)'
        return
    }

    # tree-sitter-cli : nvim-treesitter parser compilation. npm ships a
    #   prebuilt binary, so unlike the cargo route in machine-setup.sh this
    #   needs no Rust toolchain and no MSVC linker.
    # live-server     : HTML live preview (live-server.nvim)
    $packages = @(
        @{ Package = 'tree-sitter-cli'; Binary = 'tree-sitter' },
        @{ Package = 'live-server';     Binary = 'live-server' }
    )

    foreach ($p in $packages) {
        if (Test-CommandExists $p.Binary) {
            Write-Skip "$($p.Package) ($(Get-VersionLine $p.Binary))"
            continue
        }
        Write-Step "npm install -g $($p.Package)"
        & npm install -g $p.Package --silent *> $null
        if ($LASTEXITCODE -eq 0) {
            Update-SessionPath
            Write-Ok "$($p.Package) installed"
        } else {
            Write-Fail "$($p.Package) - npm exit $LASTEXITCODE"
            $script:Failures += "$($p.Package) (npm exit $LASTEXITCODE)"
        }
    }
}

# -------------------------------------------------------------
# Python + uv
# -------------------------------------------------------------
function Install-Python {
    Write-Section 'Python + uv'

    # The Microsoft Store python.exe stub reports as present but is not a real
    # interpreter, so probe for a version string rather than trusting the alias.
    $realPython = $false
    if (Test-CommandExists 'python') {
        $v = Get-VersionLine 'python'
        if ($v -match 'Python \d+\.\d+') { $realPython = $true; Write-Skip "python ($v)" }
    }
    if (-not $realPython) {
        Install-WingetPackage -Id 'Python.Python.3.13' -Label 'python' | Out-Null
    }

    Install-WingetPackage -Id 'astral-sh.uv' -Label 'uv' -ProbeCommand 'uv' | Out-Null
}

# -------------------------------------------------------------
# Rust
# -------------------------------------------------------------
function Install-Rust {
    Write-Section 'Rust (rustup)'

    if ($SkipRust) { Write-Warn 'Skipping Rust (-SkipRust)'; return }
    if (Test-CommandExists 'cargo') { Write-Skip "cargo ($(Get-VersionLine 'cargo'))"; return }

    if (Install-WingetPackage -Id 'Rustlang.Rustup' -Label 'rustup' -ProbeCommand 'rustup') {
        Update-SessionPath
        # rustup defaults to the msvc toolchain, which needs Visual Studio
        # Build Tools. We install WinLibs gcc above, so prefer the gnu
        # toolchain and keep this script free of a multi-GB VS dependency.
        if (Test-CommandExists 'rustup') {
            Write-Step 'selecting the gnu toolchain (avoids needing VS Build Tools)'
            & rustup default stable-x86_64-pc-windows-gnu *> $null
            if ($LASTEXITCODE -eq 0) { Write-Ok 'rustup default = stable-gnu' }
            else { Write-Warn 'could not set gnu toolchain; rust_analyzer may need VS Build Tools' }
        }
    }
}

# -------------------------------------------------------------
# Yazi
# -------------------------------------------------------------
function Install-Yazi {
    Write-Section 'Yazi file manager'
    Install-WingetPackage -Id 'sxyazi.yazi' -Label 'yazi' -ProbeCommand 'yazi' | Out-Null
}

# -------------------------------------------------------------
# Go (zip)
# -------------------------------------------------------------
# The Go MSI installs to C:\Program Files\Go and needs UAC; the zip does not.
function Install-Go {
    if ($SkipGo) { Write-Section 'Go'; Write-Warn 'Skipping Go (-SkipGo)'; return }

    if ($script:EffectiveMode -eq 'Admin') {
        Write-Section 'Go (machine-wide MSI)'
        Install-WingetPackage -Id 'GoLang.Go' -Label 'go' -ProbeCommand 'go' | Out-Null
        return
    }

    Write-Section 'Go (portable zip)'
    if (Test-CommandExists 'go') { Write-Skip "go ($(Get-VersionLine 'go' @('version')))"; return }

    try {
        # go.dev publishes the current version list as JSON.
        $rel = Invoke-RestMethod -Uri 'https://go.dev/dl/?mode=json' -UseBasicParsing | Select-Object -First 1
        $ver = $rel.version   # e.g. go1.27.0
        Write-Step "latest Go is $ver"
        $dir = Install-FromZip `
            -Url "https://go.dev/dl/$ver.windows-amd64.zip" `
            -Label $ver -FinalName 'go'
        Add-UserPath (Join-Path $dir 'bin')
    } catch {
        Write-Fail "go - $($_.Exception.Message)"
        $script:Failures += 'go'
    }
}

# -------------------------------------------------------------
# Java (zip) - needed for jdtls
# -------------------------------------------------------------
# The Temurin MSI needs UAC. The zip does not. jdtls also wants JAVA_HOME.
function Install-Java {
    if ($SkipJava) { Write-Section 'Java'; Write-Warn 'Skipping Java (-SkipJava)'; return }

    if ($script:EffectiveMode -eq 'Admin') {
        Write-Section 'Java (Temurin JDK 21, machine-wide MSI)'
        # The Temurin MSI sets JAVA_HOME itself, so nothing extra to wire.
        Install-WingetPackage -Id 'EclipseAdoptium.Temurin.21.JDK' -Label 'jdk' -ProbeCommand 'java' | Out-Null
        return
    }

    Write-Section 'Java (Temurin JDK 21, portable zip)'
    if (Test-CommandExists 'java') { Write-Skip "java ($(Get-VersionLine 'java' @('-version')))"; return }

    try {
        $dir = Install-FromZip `
            -Url 'https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse' `
            -Label 'Temurin JDK 21' -FinalName 'jdk-21' -RootPattern 'jdk-21*'
        Add-UserPath (Join-Path $dir 'bin')
        [Environment]::SetEnvironmentVariable('JAVA_HOME', $dir, 'User')
        $env:JAVA_HOME = $dir
        Write-Ok "JAVA_HOME = $dir"
    } catch {
        Write-Fail "java - $($_.Exception.Message)"
        $script:Failures += 'java'
    }
}

# -------------------------------------------------------------
# .NET SDK - needed for omnisharp
# -------------------------------------------------------------
# This is the one dependency that cannot be installed without admin.
# Report rather than fail: it is usually present on a corporate image.
function Test-Dotnet {
    Write-Section '.NET SDK (omnisharp)'

    if ($SkipDotnet) { Write-Warn 'Skipping .NET (-SkipDotnet)'; return }

    if (Test-CommandExists 'dotnet') {
        $sdks = @(& dotnet --list-sdks 2>&1)
        if ($sdks -and $sdks.Count -gt 0 -and $sdks[0] -match '^\d') {
            Write-Skip "dotnet SDK present: $($sdks[0])"
            return
        }
        Write-Warn 'dotnet is present but no SDK is installed (runtime only).'
    } else {
        Write-Warn 'dotnet not found.'
    }

    if ($script:EffectiveMode -eq 'Admin') {
        Install-WingetPackage -Id 'Microsoft.DotNet.SDK.8' -Label 'dotnet-sdk' | Out-Null
        return
    }

    Write-Warn 'The .NET SDK installer requires administrator rights, and this'
    Write-Warn 'is User mode. omnisharp (C# LSP) will not work until it is'
    Write-Warn 'installed. Re-run with -Mode Admin from an elevated shell, ask'
    Write-Warn 'IT to deploy it, or remove `omnisharp` from the servers table'
    Write-Warn 'in init.lua to stop Mason retrying it.'
    $script:Failures += '.NET SDK (needs admin; omnisharp only)'
}

# -------------------------------------------------------------
# LaTeX - needed for vimtex + latexmk
# -------------------------------------------------------------
# MiKTeX rather than TeX Live: it installs per-user, ships latexmk, and
# fetches missing packages on demand, keeping the initial download small.
# SumatraPDF is the viewer, matching vimtex_view_method = 'sumatrapdf'.
# zathura has no usable native Windows build.
function Install-Latex {
    Write-Section 'LaTeX (MiKTeX + SumatraPDF)'

    if ($SkipLatex) { Write-Warn 'Skipping LaTeX (-SkipLatex)'; return }

    if (Test-CommandExists 'latexmk') {
        Write-Skip 'LaTeX (latexmk found)'
    } else {
        Write-Warn 'MiKTeX is a large install. Press Ctrl-C within 5s to skip.'
        Start-Sleep -Seconds 5
        Install-WingetPackage -Id 'MiKTeX.MiKTeX' -Label 'miktex' -ProbeCommand 'miktex' | Out-Null
    }

    Install-WingetPackage -Id 'SumatraPDF.SumatraPDF' -Label 'sumatrapdf' | Out-Null
}

# -------------------------------------------------------------
# Summary
# -------------------------------------------------------------
function Write-NextSteps {
    Write-Host ''
    Write-Host '=============================================='
    if ($script:Failures.Count -eq 0) {
        Write-Host '  Setup complete.' -ForegroundColor Green
    } else {
        Write-Host '  Setup finished with notes.' -ForegroundColor Yellow
    }
    Write-Host '=============================================='

    if ($script:Failures.Count -gt 0) {
        Write-Host ''
        Write-Host '  Not installed:' -ForegroundColor Yellow
        foreach ($f in $script:Failures) { Write-Host "    - $f" }
    }

    Write-Host ''
    Write-Host '  Next steps:'
    Write-Host '  1. Open a NEW shell so the updated user PATH is picked up.'
    Write-Host '  2. Run: nvim'
    Write-Host '     vim.pack installs plugins, then Mason installs the LSP'
    Write-Host '     servers, linters and formatters on first launch.'
    Write-Host '  3. Run :checkhealth to confirm everything resolved.'
    Write-Host ''
    Write-Host '  Treesitter parsers compile asynchronously on first launch.'
    Write-Host '  Give it a minute, then confirm with:'
    Write-Host '     :lua print(#require("nvim-treesitter").get_installed("parsers"))'
    Write-Host ''
    Write-Host '  One-time per machine (not handled here):'
    Write-Host '  * Obsidian vault - point OBSIDIAN_VAULT at your vault:'
    Write-Host '      [Environment]::SetEnvironmentVariable("OBSIDIAN_VAULT", "C:\path\to\vault", "User")'
    Write-Host '    init.lua creates the directory if it does not exist.'
    Write-Host '  * A Nerd Font, if you want icons. Then set'
    Write-Host '    vim.g.have_nerd_font = true in init.lua:'
    Write-Host '      winget install --id DEVCOM.JetBrainsMonoNerdFont --scope user'
    Write-Host ''
}

# -------------------------------------------------------------
# Main
# -------------------------------------------------------------
function Invoke-Main {
    Write-Host '=============================================='
    Write-Host '           machine-setup.ps1'
    Write-Host '   Neovim config - Windows system dependencies'
    Write-Host '   (no administrator rights required)'
    Write-Host '=============================================='

    if (-not (Test-CommandExists 'winget')) {
        Write-Fail 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
        exit 1
    }

    # Resolve -Mode Auto against the real elevation state of this shell.
    $elevated = Test-Elevated
    $script:EffectiveMode = if ($Mode -eq 'Auto') { if ($elevated) { 'Admin' } else { 'User' } } else { $Mode }

    Write-Host ''
    Write-Host ('  OS         : ' + (Get-CimInstance Win32_OperatingSystem).Caption)
    Write-Host ('  PowerShell : ' + $PSVersionTable.PSVersion)
    Write-Host ('  Profile    : ' + $env:USERPROFILE)
    Write-Host ('  Programs   : ' + $script:ProgramsDir)
    Write-Host ('  Elevated   : ' + $elevated)
    Write-Host ('  Mode       : ' + $script:EffectiveMode + $(if ($Mode -eq 'Auto') { ' (auto-detected)' } else { ' (requested)' }))

    if ($script:EffectiveMode -eq 'Admin' -and -not $elevated) {
        Write-Warn '-Mode Admin was requested but this shell is NOT elevated.'
        Write-Warn 'Machine-wide MSIs will raise a UAC prompt each, and will fail'
        Write-Warn 'with exit 1602 if it is declined or unavailable.'
        Write-Warn 'If you only have policy-scoped elevation (Intune EPM et al),'
        Write-Warn 'use -Mode User instead -- it needs no rights at all.'
    }
    if ($script:EffectiveMode -eq 'User') {
        Write-Host '  No elevation needed: user-scope winget + portable zips.'
    }

    Update-SessionPath

    Install-BaseTools
    Install-Neovim
    Install-Win32Yank
    Install-Node
    Install-NpmPackages
    Install-Python
    Install-Rust
    Install-Yazi
    Install-Go
    Install-Java
    Test-Dotnet
    Install-Latex

    Write-NextSteps
}

Invoke-Main
