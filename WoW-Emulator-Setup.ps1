#Requires -Version 5.1
<#
.SYNOPSIS
    WoW Emulator Setup: an interactive wizard that sets up AzerothCore or
    TrinityCore 3.3.5a on Windows.

.NOTES
    Version: see $WizardVersion below. Changes are listed in CHANGELOG.md.
    License: MIT (see LICENSE).

.DESCRIPTION
    Follows each project's official install guides, in order:

      AzerothCore (https://www.azerothcore.org/wiki/)
        Step 1  Requirements        windows-requirements
        Step 2  Core installation   windows-core-installation
        Step 3  Server setup        windows-server-setup
        Step 4  Database setup      database-installation
        Step 5  Networking          networking

      TrinityCore (https://trinitycore.info/en/install/)
        Step 1  Requirements        requirements/windows
        Step 2  Core installation   Core-Installation/windows-core-installation
        Step 3  Server setup        Server-Setup/Windows-Server-Setup
        Step 4  Database setup      Database-Installation
        Step 5  Networking          realmlist address + firewall

    Run everything at once, or pick a single step from the menu. Every step
    checks what is already done first, so it is safe to re-run. Answers are
    remembered per core in wizard-settings*.json (passwords are never saved there).

    Start it with Start-Setup.bat (double-click), or:
        powershell -ExecutionPolicy Bypass -File .\WoW-Emulator-Setup.ps1
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# Shared settings
# ---------------------------------------------------------------------------
$WizardName       = 'WoW Emulator Setup'
$WizardVersion    = '0.9.0'
$BuildConfig      = 'RelWithDebInfo'
$OpenSslHashesUrl = 'https://github.com/slproweb/opensslhashes/raw/master/win32_openssl_hashes.json'
$LogFile          = Join-Path $PSScriptRoot 'setup-log.txt'

# ---------------------------------------------------------------------------
# Server cores. Minimum versions come from each project's Windows requirements page.
# Select-Core copies the chosen profile's values into the script variables
# ($MinBoost, $Sources, ...) that the rest of the wizard uses.
# ---------------------------------------------------------------------------
$Cores = @(
    @{
        Name           = 'AzerothCore'
        Tagline        = 'Playerbots, modules, pre-extracted client data download'
        SettingsFile   = 'wizard-settings.json'
        DefaultBaseDir = 'C:\AzerothCore'
        SrcFolder      = 'azerothcore-wotlk'
        Solution       = 'AzerothCore.sln'
        MinMySql       = [version]'8.0.0'
        MinBoost       = [version]'1.78.0'
        MinCMake       = [version]'3.16.0'
        MinVs          = '17.0'
        Boost          = @{ Pinned = '1.78.0'; PinnedUrl = 'https://sourceforge.net/projects/boost/files/boost-binaries/1.78.0/boost_1_78_0-msvc-14.3-64.exe/download' }
        ToolsOption    = @{ Name = 'TOOLS_BUILD'; On = 'all'; Off = 'none' }
        ConfigsSubdir  = 'configs'
        DbUser         = 'acore'
        DbAuth         = 'acore_auth'
        DbWorld        = 'acore_world'
        DbCharacters   = 'acore_characters'
        Extractors     = @('map_extractor.exe', 'vmap4_extractor.exe', 'vmap4_assembler.exe', 'mmaps_generator.exe', 'mmaps-config.yaml')
        ExtractorBat   = 'apps\extractor\extractor.bat'
        ClientDataApi  = 'https://api.github.com/repos/wowgaming/client-data/releases/latest'
        ClientDataZip  = 'https://github.com/wowgaming/client-data/releases/download/v20.0/Data.zip'
        WorldDbRelease = $null
        # The authserver creates the auth database (and realmlist) on its first start.
        AuthDbCreator  = 'authserver'
        Sources        = @(
            @{ Label = 'Playerbots fork (required if you want bots)'; Url = 'https://github.com/mod-playerbots/azerothcore-wotlk.git'; Branch = 'Playerbot'; IsFork = $true },
            @{ Label = 'Stock AzerothCore';                            Url = 'https://github.com/azerothcore/azerothcore-wotlk.git';    Branch = 'master';    IsFork = $false }
        )
        Modules        = @(
            @{ Name = 'mod-playerbots';  Url = 'https://github.com/mod-playerbots/mod-playerbots.git'; Desc = 'AI player bots (Playerbots fork only)'; RequiresFork = $true;  Default = $true  },
            @{ Name = 'mod-autobalance'; Url = 'https://github.com/azerothcore/mod-autobalance.git';   Desc = 'Scales dungeons/raids to group size';   RequiresFork = $false; Default = $true  },
            @{ Name = 'mod-solo-lfg';    Url = 'https://github.com/azerothcore/mod-solo-lfg.git';      Desc = 'Queue for dungeons solo';               RequiresFork = $false; Default = $false },
            @{ Name = 'mod-transmog';    Url = 'https://github.com/azerothcore/mod-transmog.git';      Desc = 'Transmogrification NPC';                RequiresFork = $false; Default = $false },
            @{ Name = 'mod-ah-bot';      Url = 'https://github.com/azerothcore/mod-ah-bot.git';        Desc = 'Fills the auction house';               RequiresFork = $false; Default = $false }
        )
    },
    @{
        Name           = 'TrinityCore'
        Tagline        = 'the classic 3.3.5 branch; client data is extracted from your own WoW client'
        SettingsFile   = 'wizard-settings-trinitycore.json'
        DefaultBaseDir = 'C:\TrinityCore'
        SrcFolder      = 'TrinityCore'
        Solution       = 'TrinityCore.sln'
        MinMySql       = [version]'8.0.34'
        MinBoost       = [version]'1.80.0'
        MinCMake       = [version]'3.24.0'
        MinVs          = '17.4'
        # The guide recommends the latest stable Boost; 1.84 is what TrinityCore's own Windows CI builds with.
        Boost          = @{ Latest = $true; Tested = '1.84.0' }
        ToolsOption    = @{ Name = 'TOOLS'; On = '1'; Off = '0' }
        ConfigsSubdir  = ''
        DbUser         = 'trinity'
        DbAuth         = 'auth'
        DbWorld        = 'world'
        DbCharacters   = 'characters'
        Extractors     = @('mapextractor.exe', 'vmap4extractor.exe', 'vmap4assembler.exe', 'mmaps_generator.exe')
        ExtractorBat   = 'contrib\extractor.bat'
        ClientDataApi  = $null
        ClientDataZip  = $null
        # The worldserver imports this TDB file into the world database on its first start.
        WorldDbRelease = @{ Api = 'https://api.github.com/repos/TrinityCore/TrinityCore/releases?per_page=50'; TagPrefix = 'TDB335.'; FilePattern = 'TDB_full_world_335*.sql' }
        # authserver.conf has Updates.EnableDatabases = 0; the worldserver creates all databases.
        AuthDbCreator  = 'worldserver'
        Sources        = @(
            @{ Label = 'TrinityCore 3.3.5 branch'; Url = 'https://github.com/TrinityCore/TrinityCore.git'; Branch = '3.3.5'; IsFork = $false }
        )
        Modules        = @()
    }
)

# Set by Select-Core
$script:Core          = $null
$DefaultBaseDir       = $null
$MinMySql             = $null
$MinBoost             = $null
$MinCMake             = $null
$SettingsFile         = $null
$Sources              = @()
$ModuleCatalog        = @()

# Filled in as the wizard runs
$script:Settings    = @{}
$script:Paths       = $null
$script:MySql       = $null
$script:Git         = $null
$script:CMake       = $null
$script:OpenSslRoot = $null

# ---------------------------------------------------------------------------
# Console helpers
# ---------------------------------------------------------------------------
function Write-Header([string]$Text) {
    Write-Host ''
    Write-Host ('=' * 65) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 65) -ForegroundColor Cyan
}
function Write-Step([string]$Text) { Write-Host "[+] $Text" }
function Write-Ok([string]$Text)   { Write-Host "[OK] $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "[!] $Text" -ForegroundColor Yellow }
function Write-Fail([string]$Text) { Write-Host "[X] $Text" -ForegroundColor Red }

function Stop-Wizard([string]$Message) {
    throw [System.OperationCanceledException]::new($Message)
}

function Read-YesNo([string]$Question, [bool]$Default = $true) {
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $a = "$(Read-Host "$Question $hint")".Trim().ToLower()
        if ($a -eq '') { return $Default }
        if ($a -in 'y', 'yes') { return $true }
        if ($a -in 'n', 'no') { return $false }
        Write-Warn 'Please answer y or n.'
    }
}

function Read-Choice([string]$Question, [string[]]$Options, [int]$Default = 1) {
    Write-Host $Question
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("  {0}) {1}" -f ($i + 1), $Options[$i])
    }
    while ($true) {
        $a = "$(Read-Host "Choose 1-$($Options.Count) [default $Default]")".Trim()
        if ($a -eq '') { return $Default - 1 }
        $n = 0
        if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n - 1 }
        Write-Warn 'Invalid choice.'
    }
}

function Read-Text([string]$Prompt, [string]$Default) {
    $a = "$(Read-Host "$Prompt [default: $Default]")".Trim()
    if ($a -eq '') { return $Default }
    return $a
}

# Password prompt that is not echoed and not written to the transcript.
function Read-Secret([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# Folder picker window, falls back to typing a path if Windows Forms is unavailable.
function Select-Folder([string]$Description, [string]$StartPath) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = $Description
        if ($StartPath -and (Test-Path $StartPath)) { $dlg.SelectedPath = $StartPath }
        Write-Host "    (a folder picker window has opened: $Description)"
        $result = $dlg.ShowDialog($owner)
        $owner.Dispose()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
        return $null
    } catch {
        $p = Read-Host "$Description (paste the full path)"
        if ($p) { return $p.Trim('" ') }
        return $null
    }
}

# ---------------------------------------------------------------------------
# Saved answers
# ---------------------------------------------------------------------------
function Import-Settings {
    if (-not (Test-Path $SettingsFile)) { return }
    try {
        $obj = Get-Content $SettingsFile -Raw | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) { $script:Settings[$p.Name] = $p.Value }
    } catch {
        Write-Warn "Could not read $SettingsFile, starting fresh."
    }
}

function Save-Setting([string]$Name, $Value) {
    $script:Settings[$Name] = $Value
    [pscustomobject]$script:Settings | ConvertTo-Json | Set-Content -Path $SettingsFile -Encoding UTF8
}

# ---------------------------------------------------------------------------
# System helpers
# ---------------------------------------------------------------------------
# Reload PATH from the registry so freshly installed tools work without a reboot.
function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# Tells Explorer and new programs that environment variables changed.
function Send-EnvironmentChange {
    if (-not ('AcWizard.NativeMethods' -as [type])) {
        Add-Type -Namespace AcWizard -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    [AcWizard.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result) | Out-Null
}

# Appends a folder to the system PATH without the 1024-character truncation
# of setx and without expanding %VARIABLES% already in it.
function Add-ToMachinePath([string]$Dir) {
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    $raw = (Get-Item $key).GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $parts = @($raw -split ';' | Where-Object { $_ })
    if ($parts | Where-Object { $_.TrimEnd('\') -eq $Dir.TrimEnd('\') }) { return }
    Set-ItemProperty -Path $key -Name Path -Value (($parts + $Dir) -join ';') -Type ExpandString
    Send-EnvironmentChange
    Update-SessionPath
    Write-Ok "Added to system PATH: $Dir"
}

function Invoke-Winget {
    param([string]$Id, [string]$Version, [string]$Override)
    $wgArgs = @('install', '--id', $Id, '-e', '--source', 'winget',
                '--accept-package-agreements', '--accept-source-agreements')
    if ($Version)  { $wgArgs += @('--version', $Version) }
    if ($Override) { $wgArgs += @('--override', $Override) } else { $wgArgs += '--silent' }

    Write-Step "winget install $Id $Version"
    & winget @wgArgs | Out-Host
    $code = $LASTEXITCODE
    Update-SessionPath
    if ($code -ne 0) { Write-Warn "winget exited with code $code for $Id" }
    return ($code -eq 0)
}

function Test-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    # winget.exe is an app alias here; a fresh install is not on this session's PATH yet.
    $apps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    if (Test-Path (Join-Path $apps 'winget.exe')) { $env:Path += ";$apps"; return $true }
    return $false
}

# winget is missing on Windows Sandbox, LTSC/Server editions and some older Windows 10
# installs. Microsoft's documented fix is the Microsoft.WinGet.Client PowerShell module.
function Install-WingetIfMissing {
    if (Test-Winget) { Write-Ok 'winget available'; return }
    Write-Warn 'winget (the Windows package manager) was not found. The wizard uses it to install the other tools.'
    if (Read-YesNo 'Install winget now?') {
        try {
            Write-Step 'Installing winget (this can take a few minutes)...'
            $ProgressPreference = 'SilentlyContinue'
            Install-PackageProvider -Name NuGet -Force | Out-Null
            Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
            Import-Module Microsoft.WinGet.Client
            Repair-WinGetPackageManager -AllUsers | Out-Null
            Update-SessionPath
        } catch {
            Write-Fail "Automatic winget install failed: $($_.Exception.Message)"
        }
    }
    if (Test-Winget) { Write-Ok 'winget installed'; return }
    Write-Fail 'winget is still missing. Install "App Installer" from the Microsoft Store (or from github.com/microsoft/winget-cli/releases), then re-run.'
    Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1' -ErrorAction SilentlyContinue
    Stop-Wizard 'winget is required.'
}

# Downloads with curl.exe (ships with Windows 10+): shows progress, skips the download
# if the file is already complete, and when a server drops the connection it resumes
# where it stopped. Several URLs can be given (mirrors of the same file); each is tried
# in turn, and a partial file from one mirror is resumed from the next.
function Save-Download([string[]]$Urls, [string]$OutFile, [int]$Attempts = 4) {
    foreach ($url in $Urls) {
        if (Test-Path $OutFile) {
            $head = (& curl.exe -sIL $url) | Out-String
            $sizes = [regex]::Matches($head, '(?im)^content-length:\s*(\d+)')
            if ($sizes.Count -gt 0 -and [int64]$sizes[$sizes.Count - 1].Groups[1].Value -eq (Get-Item $OutFile).Length) {
                Write-Ok "$(Split-Path $OutFile -Leaf) already downloaded"
                return
            }
        }
        for ($i = 1; $i -le $Attempts; $i++) {
            & curl.exe -L --fail -C - -o $OutFile $url
            $code = $LASTEXITCODE
            if ($code -eq 0) { return }
            # 33: the server can't resume, so start that file over.
            if ($code -eq 33) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
            # 22: HTTP error (404, 5xx); retrying the same mirror rarely helps.
            if ($code -eq 22) { break }
            if ($i -lt $Attempts) {
                Write-Warn "Download interrupted (curl error $code). Resuming in 5 seconds (attempt $($i + 1) of $Attempts)..."
                Start-Sleep -Seconds 5
            }
        }
        if ($Urls.Count -gt 1 -and $url -ne $Urls[-1]) { Write-Warn "$url is not working right now, trying another mirror..." }
    }
    throw "Download failed: $($Urls -join ' and ') (run the step again to resume)"
}

function Find-Tool([string]$Command, [string[]]$Fallbacks) {
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($f in $Fallbacks) { if (Test-Path $f) { return $f } }
    return $null
}

# Runs $Detect; if it finds nothing, tries each winget id in turn. Returns what $Detect returned.
function Install-ToolIfMissing([string]$Name, [scriptblock]$Detect, [string[]]$WingetIds) {
    $found = & $Detect
    if ($found) { Write-Ok "$Name found"; return $found }
    foreach ($id in $WingetIds) {
        Invoke-Winget -Id $id | Out-Null
        $found = & $Detect
        if ($found) { Write-Ok "$Name installed"; return $found }
    }
    throw "$Name could not be installed automatically. Install it manually, then re-run the wizard."
}

$OpenSslRoots = @((Join-Path $env:ProgramFiles 'OpenSSL-Win64'), 'C:\OpenSSL-Win64')

# Major version from the installed headers (include\openssl\opensslv.h), or $null.
function Get-OpenSslMajor([string]$Root) {
    $header = Join-Path $Root 'include\openssl\opensslv.h'
    if (-not (Test-Path $header)) { return $null }
    $m = Select-String -Path $header -Pattern 'define\s+OPENSSL_VERSION_MAJOR\s+(\d+)' | Select-Object -First 1
    if ($m) { return [int]$m.Matches[0].Groups[1].Value }
    return $null
}

# Finds a full (with headers) OpenSSL 3.x install. The wiki requires 3.x;
# OpenSSL 4 renamed its DLLs and is not supported.
function Find-OpenSsl {
    foreach ($root in $OpenSslRoots) {
        if ((Test-Path (Join-Path $root 'include\openssl\ssl.h')) -and (Get-OpenSslMajor $root) -eq 3) { return $root }
    }
    return $null
}

function Install-OpenSsl3 {
    $found = Find-OpenSsl
    if ($found) { Write-Ok "OpenSSL 3 found at $found"; return $found }

    foreach ($root in $OpenSslRoots) {
        $major = Get-OpenSslMajor $root
        if ($major -and $major -ne 3) {
            Write-Warn "OpenSSL $major is installed at $root, but $($script:Core.Name) needs OpenSSL 3.x."
            if (-not (Read-YesNo "Uninstall OpenSSL $major and install OpenSSL 3 instead?")) {
                Stop-Wizard 'OpenSSL 3.x is required. Uninstall the other version and run Step 1 again.'
            }
            & winget uninstall --id ShiningLight.OpenSSL.Dev -e --silent --accept-source-agreements | Out-Host
            if (Get-OpenSslMajor $root) {
                Write-Warn "It is still there. Uninstall 'OpenSSL' from Settings > Apps, then press Enter."
                Read-Host | Out-Null
            }
        }
    }

    # slproweb deletes old installers when a new one comes out, so winget's links
    # for older versions go dead. Their hash list always points at live files.
    if (-not (Install-OpenSsl3FromSlproweb)) { Install-OpenSsl3FromWinget }
    # Stop "winget upgrade --all" from moving it to OpenSSL 4 later.
    & winget pin add --id ShiningLight.OpenSSL.Dev --version '3.*' --accept-source-agreements | Out-Null

    $found = Find-OpenSsl
    if (-not $found) {
        Start-Process 'https://slproweb.com/products/Win32OpenSSL.html'
        Stop-Wizard 'OpenSSL 3 could not be installed automatically. Install the newest "Win64 OpenSSL v3.x" (not Light) from the page that just opened, then run Step 1 again.'
    }
    Write-Ok "OpenSSL 3 installed at $found"
    return $found
}

# Newest full (not Light) Win64 OpenSSL 3.x MSI from slproweb's published list, checksum-verified.
function Install-OpenSsl3FromSlproweb {
    try {
        $list = Invoke-RestMethod -Uri $OpenSslHashesUrl -UseBasicParsing
    } catch {
        Write-Warn "Could not read the OpenSSL installer list: $($_.Exception.Message)"
        return $false
    }
    $pick = $list.files.PSObject.Properties | ForEach-Object { $_.Value } |
            Where-Object { $_.bits -eq 64 -and $_.arch -eq 'INTEL' -and -not $_.light -and
                           $_.installer -eq 'msi' -and $_.basever -like '3.*' } |
            Sort-Object { [version]$_.basever } -Descending | Select-Object -First 1
    if (-not $pick) { Write-Warn 'No OpenSSL 3.x installer in the list.'; return $false }

    $msi = Join-Path $env:TEMP (Split-Path $pick.url -Leaf)
    Write-Step "Downloading OpenSSL $($pick.basever) ($([math]::Round($pick.size / 1MB)) MB)..."
    Save-Download $pick.url $msi
    if ((Get-FileHash $msi -Algorithm SHA256).Hash -ne $pick.sha256.ToUpper()) {
        Remove-Item $msi -Force
        Write-Warn 'Checksum mismatch on the OpenSSL download; discarded it.'
        return $false
    }
    Write-Step "Installing OpenSSL $($pick.basever)..."
    $proc = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @('/i', "`"$msi`"", '/qn', '/norestart')
    Remove-Item $msi -Force -ErrorAction SilentlyContinue
    if ($proc.ExitCode -notin 0, 3010) { Write-Warn "OpenSSL installer exited with code $($proc.ExitCode)"; return $false }
    return [bool](Find-OpenSsl)
}

# Fallback: try winget's 3.x versions newest first until one still downloads.
function Install-OpenSsl3FromWinget {
    $versions = (& winget show --id ShiningLight.OpenSSL.Dev -e --versions --accept-source-agreements) | Out-String
    $v3s = [regex]::Matches($versions, '(?m)^\s*(3\.\d+\.\d+)\s*$') |
           ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending
    foreach ($v in $v3s) {
        if ((Invoke-Winget -Id 'ShiningLight.OpenSSL.Dev' -Version $v.ToString()) -and (Find-OpenSsl)) { return }
        Write-Warn "OpenSSL $v failed, trying an older 3.x version..."
    }
}

function Resolve-BuildTools {
    if (-not $script:Git)   { $script:Git   = Find-Tool 'git'   @("$env:ProgramFiles\Git\cmd\git.exe") }
    if (-not $script:CMake) { $script:CMake = Find-Tool 'cmake' @("$env:ProgramFiles\CMake\bin\cmake.exe") }
    if (-not $script:OpenSslRoot) { $script:OpenSslRoot = Find-OpenSsl }
    if (-not ($script:Git -and $script:CMake -and $script:OpenSslRoot)) {
        throw 'Git, CMake or OpenSSL 3 is missing. Run Step 1 (Requirements) first.'
    }
}

# ---------------------------------------------------------------------------
# Config file helpers (*.conf)
# ---------------------------------------------------------------------------
function Get-ConfValue([string]$File, [string]$Key) {
    if (-not (Test-Path $File)) { return $null }
    $m = Select-String -Path $File -Pattern ('^\s*' + [regex]::Escape($Key) + '\s*=\s*"?([^"\r\n]*)"?') | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return $null
}

# Replaces "Key = ..." in a .conf file. $Value is written as-is, so quote strings yourself.
function Set-ConfValue([string]$File, [string]$Key, [string]$Value) {
    $text = [IO.File]::ReadAllText($File)
    $pattern = '(?m)^[ \t]*' + [regex]::Escape($Key) + '[ \t]*=[^\r\n]*'
    $line = "$Key = $Value"
    if ([regex]::IsMatch($text, $pattern)) {
        $text = [regex]::Replace($text, $pattern, { param($m) $line }.GetNewClosure(), 1)
    } else {
        $text = $text.TrimEnd() + "`r`n$line`r`n"
    }
    [IO.File]::WriteAllText($File, $text, (New-Object Text.UTF8Encoding $false))
}

# ---------------------------------------------------------------------------
# Install location
# ---------------------------------------------------------------------------
function Resolve-Paths {
    if ($script:Paths) { return $script:Paths }
    $base = $script:Settings.BaseDir
    if ($base) {
        Write-Ok "Install folder: $base"
    } else {
        $base = $DefaultBaseDir
        if (-not (Read-YesNo "Install $($script:Core.Name) into $base ?")) {
            $base = Select-Folder "Choose where to install $($script:Core.Name)" 'C:\'
            if (-not $base) { Stop-Wizard 'No install folder chosen.' }
        }
        if ($base -like '*OneDrive*') { Write-Warn "Building inside OneDrive is slow and can break. A plain folder like $DefaultBaseDir is better." }
        Save-Setting 'BaseDir' $base
    }
    $build = Join-Path $base 'build'
    $output = Join-Path $build "bin\$BuildConfig"
    $server = Join-Path $base 'server'
    # Once Step 6 has created the server folder, the server runs (and is configured) from
    # there; until then it runs straight from the build output.
    $published = Test-Path (Join-Path $server 'worldserver.exe')
    $bin = if ($published) { $server } else { $output }
    $script:Paths = [pscustomobject]@{
        Base      = $base
        Src       = (Join-Path $base $script:Core.SrcFolder)
        Build     = $build
        Output    = $output
        Server    = $server
        Published = $published
        Bin       = $bin
        # AzerothCore puts the .conf files in bin\<config>\configs, TrinityCore next to the exes.
        Configs = $(if ($script:Core.ConfigsSubdir) { Join-Path $bin $script:Core.ConfigsSubdir } else { $bin })
        Data    = (Join-Path $bin 'Data')
    }
    return $script:Paths
}

# ---------------------------------------------------------------------------
# Visual Studio
# ---------------------------------------------------------------------------
function Get-VisualStudio {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $null }
    $cpp = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
    # 2022 or newer (TrinityCore: 17.4+); both guides say no previews, which vswhere skips by default
    $range = "[$($script:Core.MinVs),)"

    $path = & $vswhere -latest -products * -version $range -requires $cpp -property installationPath
    $ver  = & $vswhere -latest -products * -version $range -requires $cpp -property installationVersion
    $hasCpp = [bool]$path
    if (-not $hasCpp) {
        $path = & $vswhere -latest -products * -version $range -property installationPath
        $ver  = & $vswhere -latest -products * -version $range -property installationVersion
    }
    if (-not $path) { return $null }
    [pscustomobject]@{ Path = "$path".Trim(); Major = [int]("$ver".Split('.')[0]); HasCpp = $hasCpp }
}

function Initialize-VisualStudio {
    $vs = Get-VisualStudio
    if (-not $vs) {
        Write-Step 'Installing Visual Studio 2022 Community with "Desktop development with C++" (20-60 minutes)...'
        Invoke-Winget -Id 'Microsoft.VisualStudio.2022.Community' `
            -Override '--wait --passive --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended' | Out-Null
        $vs = Get-VisualStudio
        if (-not $vs) {
            throw "No Visual Studio $($script:Core.MinVs) or newer with C++ found. If an older Visual Studio 2022 is installed, update it from the Visual Studio Installer; otherwise install Visual Studio 2022 with 'Desktop development with C++' manually."
        }
    }

    if (-not $vs.HasCpp) {
        Write-Warn "Visual Studio found at $($vs.Path), but 'Desktop development with C++' is missing."
        if (Read-YesNo 'Add the C++ workload now?') {
            $setup = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\setup.exe'
            Start-Process -FilePath $setup -Wait -ArgumentList @(
                'modify', '--installPath', "`"$($vs.Path)`"",
                '--add', 'Microsoft.VisualStudio.Workload.NativeDesktop', '--includeRecommended',
                '--passive', '--norestart')
            $vs = Get-VisualStudio
        }
        if (-not $vs.HasCpp) { throw 'The Visual Studio C++ workload is required. Add it with the Visual Studio Installer and re-run.' }
    }

    $generator = switch ($vs.Major) {
        17 { 'Visual Studio 17 2022' }
        18 { 'Visual Studio 18 2026' }
        default { $null }
    }
    if (-not $generator) { throw "Unsupported Visual Studio major version $($vs.Major)." }
    Write-Ok "Visual Studio with C++ tools ($generator)"
    return $generator
}

# ---------------------------------------------------------------------------
# MySQL (WAMP or standalone)
# ---------------------------------------------------------------------------
function Get-MySqlVersion([string]$BinDir) {
    foreach ($exe in 'mysqld.exe', 'mysql.exe') {
        $p = Join-Path $BinDir $exe
        if (-not (Test-Path $p)) { continue }
        try { $out = (& $p --version) | Out-String } catch { continue }
        if ($out -match 'MariaDB') { return [pscustomobject]@{ Version = $null; IsMariaDB = $true } }
        if ($out -match 'Ver\s+(\d+\.\d+\.\d+)') {
            return [pscustomobject]@{ Version = [version]$Matches[1]; IsMariaDB = $false }
        }
    }
    return $null
}

# Only the 8.x line (AzerothCore wiki: "MySQL 26.x.x is not supported. Use MySQL 8.4 LTS"),
# at or above the core's minimum (TrinityCore: 8.0.34).
function Test-MySqlVersionOk([version]$Version) {
    return ($Version -ge $MinMySql -and $Version.Major -eq 8)
}

# Reads the server port from my.ini. WAMP names its server section [wampmysqld64].
function Get-MySqlPort([string]$IniPath) {
    if (Test-Path $IniPath) {
        $section = ''
        foreach ($line in Get-Content $IniPath) {
            if ($line -match '^\s*\[(.+?)\]') { $section = $Matches[1].ToLower(); continue }
            if (($section -eq 'mysqld' -or $section -like 'wampmysqld*') -and $line -match '^\s*port\s*=\s*(\d+)') {
                return [int]$Matches[1]
            }
        }
    }
    return 3306
}

function Get-MySqlInstall([string]$Root) {
    $bin = Join-Path $Root 'bin'
    if (-not (Test-Path $bin)) { return $null }
    $info = Get-MySqlVersion $bin
    if (-not $info -and (Split-Path $Root -Leaf) -match '(\d+\.\d+\.\d+)') {
        $info = [pscustomobject]@{ Version = [version]$Matches[1]; IsMariaDB = $false }
    }
    if (-not $info -or $info.IsMariaDB) { return $null }
    $isWamp = $Root -like '*\wamp*\bin\mysql\*'
    $ini = if ($isWamp) { Join-Path $Root 'my.ini' } else { Join-Path $env:ProgramData "MySQL\$(Split-Path $Root -Leaf)\my.ini" }
    [pscustomobject]@{
        Name        = (Split-Path $Root -Leaf)
        Root        = $Root
        Bin         = $bin
        Version     = $info.Version
        Port        = (Get-MySqlPort $ini)
        IniPath     = $ini
        HasDevFiles = ((Test-Path (Join-Path $Root 'include\mysql.h')) -and (Test-Path (Join-Path $Root 'lib\libmysql.lib')))
        Source      = $(if ($isWamp) { 'WAMP' } else { 'Standalone' })
    }
}

function Find-WampRoot {
    foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
        foreach ($name in 'wamp64', 'wamp') {
            $candidate = Join-Path $drive.Root $name
            if (Test-Path (Join-Path $candidate 'bin\mysql')) { return $candidate }
        }
    }
    return $null
}

function Test-WampService($MySql) {
    $svc = Get-CimInstance Win32_Service -Filter "Name LIKE 'wampmysqld%'" |
           Where-Object { $_.PathName -like "*$($MySql.Root)*" } | Select-Object -First 1
    if (-not $svc) {
        Write-Warn "No WAMP service points at $($MySql.Name). In the WAMP tray menu, switch MySQL to this version."
        return $false
    }
    if ($svc.State -ne 'Running') {
        Write-Warn 'WAMP MySQL is not running. Start WAMP (green tray icon).'
        return $false
    }
    Write-Ok "WAMP MySQL service '$($svc.Name)' is running"
    return $true
}

function Get-WampMySql {
    $root = Find-WampRoot
    if ($root) {
        Write-Ok "Found WAMP at $root"
        if (-not (Read-YesNo 'Is this the WAMP install you want to use?')) { $root = $null }
    }
    if (-not $root) { $root = Select-Folder 'Select your WAMP folder (for example C:\wamp64)' 'C:\' }
    if (-not $root -or -not (Test-Path (Join-Path $root 'bin\mysql'))) {
        Write-Fail "No bin\mysql folder found in '$root'."
        return $null
    }

    $installs = @(Get-ChildItem (Join-Path $root 'bin\mysql') -Directory |
                  ForEach-Object { Get-MySqlInstall $_.FullName } | Where-Object { $_ })
    if ($installs.Count -eq 0) {
        Write-Fail 'WAMP has no MySQL versions installed (this wizard does not support MariaDB).'
        return $null
    }

    Write-Host ''
    Write-Host 'MySQL versions found in WAMP:'
    foreach ($i in $installs) {
        $status = if (-not (Test-MySqlVersionOk $i.Version)) { "unsupported, need 8.x ($MinMySql+, 8.4 recommended)" }
                  elseif (-not $i.HasDevFiles) { 'missing include\ or lib\ files' }
                  else { 'OK' }
        Write-Host ("  {0,-20} version {1,-9} port {2,-6} {3}" -f $i.Name, $i.Version, $i.Port, $status)
    }

    $good = @($installs | Where-Object { (Test-MySqlVersionOk $_.Version) -and $_.HasDevFiles } | Sort-Object Version -Descending)
    if ($good.Count -eq 0) { return $null }

    $pick = $good[0]
    if ($good.Count -gt 1) {
        $idx = Read-Choice "Which MySQL should $($script:Core.Name) use?" ($good | ForEach-Object { "$($_.Name) (port $($_.Port))" })
        $pick = $good[$idx]
    }
    Test-WampService $pick | Out-Null
    return $pick
}

function Find-StandaloneMySql {
    $base = Join-Path $env:ProgramFiles 'MySQL'
    if (-not (Test-Path $base)) { return $null }
    return Get-ChildItem $base -Directory -Filter 'MySQL Server*' |
           ForEach-Object { Get-MySqlInstall $_.FullName } |
           Where-Object { $_ -and (Test-MySqlVersionOk $_.Version) } |
           Sort-Object Version -Descending | Select-Object -First 1
}

function Install-MySqlServer {
    # Only the 8.4 LTS line; winget's "latest" may be an unsupported 9.x / 26.x release.
    $versions = (& winget show --id Oracle.MySQL -e --versions --accept-source-agreements) | Out-String
    $lts = [regex]::Matches($versions, '(?m)^\s*(8\.4\.\d+)\s*$') |
           ForEach-Object { [version]$_.Groups[1].Value } |
           Sort-Object -Descending | Select-Object -First 1
    if (-not $lts) {
        Start-Process 'https://dev.mysql.com/downloads/mysql/8.4.html'
        Stop-Wizard 'winget has no MySQL 8.4 package. Install MySQL 8.4 from the page that just opened, then re-run.'
    }
    Invoke-Winget -Id 'Oracle.MySQL' -Version $lts.ToString() | Out-Null
}

function Get-StandaloneMySql {
    $mysql = Find-StandaloneMySql
    if ($mysql) {
        Write-Ok "Found MySQL $($mysql.Version) at $($mysql.Root)"
    } else {
        Write-Step 'Installing MySQL 8.4 LTS...'
        Install-MySqlServer
        $mysql = Find-StandaloneMySql
        if (-not $mysql) { throw 'MySQL installation failed. Install MySQL 8.4 manually from dev.mysql.com and re-run.' }
        Write-Ok "Installed MySQL $($mysql.Version)"
    }
    if (-not $mysql.HasDevFiles) {
        throw "MySQL at $($mysql.Root) is missing include\mysql.h or lib\libmysql.lib, which are needed to compile."
    }

    $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'MySQL*' }
    if (-not $svc) {
        Write-Warn 'MySQL is installed but no server instance is configured yet.'
        $configurator = Join-Path $mysql.Bin 'mysql_configurator.exe'
        if (Test-Path $configurator) {
            Write-Host '    In MySQL Configurator:'
            Write-Host '      - set a root password and WRITE IT DOWN (you need it in Step 4)'
            Write-Host '      - keep "Configure MySQL Server as a Windows Service" ticked'
            Write-Host '      - if WAMP is also installed, use port 3307 so the two do not clash'
            if (Read-YesNo 'Open MySQL Configurator now?') {
                Start-Process -FilePath $configurator -Wait
                $mysql.Port = Get-MySqlPort $mysql.IniPath
            }
        } else {
            Write-Warn 'Run "MySQL Configurator" from the Start menu to create the server instance.'
        }
    } elseif (-not ($svc | Where-Object { $_.Status -eq 'Running' })) {
        Write-Warn "The MySQL service is not running. Start it from Task Manager > Services."
    } else {
        Write-Ok 'MySQL service is running'
    }
    return $mysql
}

function Initialize-MySql {
    if (Read-YesNo 'Do you have WAMP (WampServer) installed and want to use its MySQL?' $false) {
        $wamp = Get-WampMySql
        if ($wamp) {
            Write-Ok "Using WAMP MySQL $($wamp.Version) on port $($wamp.Port)"
            return $wamp
        }
        Write-Warn "$($script:Core.Name) needs MySQL 8.x ($MinMySql+, 8.4 recommended). You can add a MySQL 8.4 addon to WAMP from wampserver.aviatechno.net."
        $c = Read-Choice 'How do you want to continue?' @(
            'Install a standalone MySQL 8.4 server instead',
            'Exit - I will add MySQL 8.4 to WAMP and run the wizard again')
        if ($c -eq 1) { Stop-Wizard 'Add MySQL 8.4 to WAMP, then run the wizard again.' }
        Write-Warn 'WAMP normally uses port 3306, so choose port 3307 for the standalone MySQL.'
    }
    return Get-StandaloneMySql
}

# Uses the saved MySQL choice if it is still valid, otherwise asks.
function Resolve-MySql {
    if ($script:MySql) { return $script:MySql }
    $saved = $script:Settings.MySqlRoot
    $mysql = $null
    if ($saved -and (Test-Path $saved)) {
        $mysql = Get-MySqlInstall $saved
        if ($mysql -and (Test-MySqlVersionOk $mysql.Version)) {
            Write-Ok "Using $($mysql.Source) MySQL $($mysql.Version) on port $($mysql.Port)"
        } else { $mysql = $null }
    }
    if (-not $mysql) {
        $mysql = Initialize-MySql
        Save-Setting 'MySqlRoot' $mysql.Root
    }
    # The wiki asks for MySQL's bin folder on the system PATH.
    Add-ToMachinePath $mysql.Bin
    $script:MySql = $mysql
    return $mysql
}

# Runs SQL through mysql.exe. Credentials go in a temporary option file so
# they never appear on the command line; the file is deleted right after.
function Invoke-MySql {
    param([string]$User, [string]$Password, [string]$Sql, [string]$Database)
    $mysqlExe = Join-Path $script:MySql.Bin 'mysql.exe'
    $cnf = Join-Path $env:TEMP ("acwiz-{0}.cnf" -f [guid]::NewGuid().ToString('N'))
    $escUser = $User -replace '\\', '\\' -replace '"', '\"'
    $escPass = $Password -replace '\\', '\\' -replace '"', '\"'
    $lines = @('[client]', "user=`"$escUser`"", "password=`"$escPass`"", 'host=127.0.0.1',
               "port=$($script:MySql.Port)", 'default-character-set=utf8mb4')
    [IO.File]::WriteAllText($cnf, ($lines -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding $false))

    $ErrorActionPreference = 'Continue'
    $OutputEncoding = New-Object Text.UTF8Encoding $false
    try {
        $mysqlArgs = @("--defaults-extra-file=$cnf", '--batch', '--skip-column-names')
        if ($Database) { $mysqlArgs += $Database }
        $out = $Sql | & $mysqlExe @mysqlArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        Remove-Item $cnf -Force -ErrorAction SilentlyContinue
    }
    $text = (@($out) | ForEach-Object { "$_" }) -join "`n"
    return [pscustomobject]@{ Ok = ($code -eq 0); Output = $text.Trim() }
}

function ConvertTo-SqlString([string]$Value) {
    return "'" + ($Value -replace '\\', '\\' -replace "'", "''") + "'"
}

# ---------------------------------------------------------------------------
# Boost
# ---------------------------------------------------------------------------
function Get-BoostVersion([string]$Root) {
    if (-not $Root) { return $null }
    $header = Join-Path $Root 'boost\version.hpp'
    if (-not (Test-Path $header)) { return $null }
    $m = Select-String -Path $header -Pattern '#define\s+BOOST_VERSION\s+(\d+)' | Select-Object -First 1
    if (-not $m) { return $null }
    $v = [int]$m.Matches[0].Groups[1].Value
    return [version]("{0}.{1}.{2}" -f [math]::Floor($v / 100000), ([math]::Floor($v / 100) % 1000), ($v % 100))
}

# The wiki: system variable BOOST_ROOT, forward slashes, no trailing slash.
function Set-BoostRoot([string]$Path, [version]$Version) {
    if ($Version -lt $MinBoost) {
        Write-Warn "Boost $Version is older than the minimum $MinBoost."
        if (-not (Read-YesNo 'Continue anyway?' $false)) { Stop-Wizard 'Install a newer Boost and run the wizard again.' }
    }
    if (-not (Get-ChildItem $Path -Directory -Filter 'lib64-msvc-*' -ErrorAction SilentlyContinue)) {
        Write-Warn 'No lib64-msvc-* folder found. Make sure you installed the prebuilt 64-bit binaries for Visual Studio 2022, not just the source.'
    }
    $normalized = $Path.TrimEnd('\', '/') -replace '\\', '/'
    [Environment]::SetEnvironmentVariable('BOOST_ROOT', $normalized, 'Machine')
    $env:BOOST_ROOT = $normalized
    # Remembered per core and passed to CMake directly, so AzerothCore and
    # TrinityCore can each use their own Boost version.
    Save-Setting 'BoostRoot' $normalized
    Write-Ok "BOOST_ROOT = $normalized"
    return $normalized
}

# A prebuilt Boost installer (Visual Studio 2022 / MSVC 14.3, 64-bit) and where it installs.
# Boost publishes the same file on archives.boost.io and SourceForge; both are tried.
function New-BoostPackage([string]$Version, [string]$Url, [string]$Note) {
    $u = $Version -replace '\.', '_'
    $file = "boost_$u-msvc-14.3-64.exe"
    $mirrors = @("https://archives.boost.io/release/$Version/binaries/$file",
                 "https://sourceforge.net/projects/boost/files/boost-binaries/$Version/$file/download")
    if ($Url) { $mirrors = @($Url) + @($mirrors | Where-Object { $_ -ne $Url }) }
    [pscustomobject]@{ Version = $Version; Url = $mirrors[0]; Urls = $mirrors; Dir = "C:\local\boost_$u"; Installer = $file; Note = $Note }
}

# Newest Boost release on archives.boost.io that has a prebuilt MSVC 14.3 64-bit installer.
function Get-LatestBoostVersion {
    $html = (& curl.exe -sL 'https://archives.boost.io/release/') | Out-String
    $versions = [regex]::Matches($html, 'href="(\d+\.\d+\.\d+)/"') |
                ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending -Unique
    foreach ($v in $versions | Select-Object -First 3) {
        $code = & curl.exe -s -o NUL -I -L -w '%{http_code}' (New-BoostPackage $v.ToString()).Url
        if ($code -eq '200') { return $v.ToString() }
    }
    return $null
}

# The Boost versions the wizard can install for the selected core.
function Get-BoostPackages {
    $b = $script:Core.Boost
    if ($b.PinnedUrl) { return @(New-BoostPackage $b.Pinned $b.PinnedUrl "for Visual Studio 2022") }
    $list = @()
    Write-Step 'Looking up the latest stable Boost...'
    $latest = Get-LatestBoostVersion
    if ($latest) { $list += New-BoostPackage $latest $null "latest stable, recommended by the $($script:Core.Name) guide" }
    if ($latest -ne $b.Tested) { $list += New-BoostPackage $b.Tested $null "the version $($script:Core.Name)'s own Windows build is tested with" }
    return $list
}

# Downloads a prebuilt Boost and runs its Inno Setup installer silently.
# Returns the installed version, or $null on failure.
function Install-Boost($Pkg) {
    $exe = Join-Path $env:TEMP $Pkg.Installer
    Write-Step "Downloading Boost $($Pkg.Version)..."
    Save-Download $Pkg.Urls $exe
    Write-Step "Installing Boost into $($Pkg.Dir) (unpacking takes a few minutes)..."
    $proc = Start-Process -FilePath $exe -Wait -PassThru -ArgumentList @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$($Pkg.Dir)`"")
    if ($proc.ExitCode -ne 0) { Write-Fail "Boost installer exited with code $($proc.ExitCode)"; return $null }
    $v = Get-BoostVersion $Pkg.Dir
    if ($v) {
        Remove-Item $exe -Force -ErrorAction SilentlyContinue
        Write-Ok "Boost $v installed"
    }
    return $v
}

function Initialize-Boost {
    $candidates = @($script:Settings.BoostRoot, $env:BOOST_ROOT, [Environment]::GetEnvironmentVariable('BOOST_ROOT', 'Machine'))
    $candidates += @(Get-ChildItem 'C:\local' -Directory -Filter 'boost_*' -ErrorAction SilentlyContinue |
                     Sort-Object Name -Descending | ForEach-Object { $_.FullName })

    foreach ($c in ($candidates | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\', '/') -replace '\\', '/' } | Select-Object -Unique)) {
        $v = Get-BoostVersion $c
        if (-not $v) { continue }
        if ($v -lt $MinBoost) { Write-Host "    Boost $v at $c is too old for $($script:Core.Name) (needs $MinBoost+)"; continue }
        Write-Ok "Found Boost $v at $c"
        if (Read-YesNo 'Use this Boost?') { return Set-BoostRoot $c $v }
    }

    Write-Host ''
    Write-Host "No Boost $MinBoost or newer was found (or you chose not to use it)."
    $packages = @(Get-BoostPackages)
    $options = @($packages | ForEach-Object { "Download and install Boost $($_.Version) ($($_.Note), ~200 MB, into $($_.Dir))" })
    $options += 'I will download and install it myself'
    $c = Read-Choice 'How do you want to install it?' $options
    if ($c -lt $packages.Count) {
        $v = Install-Boost $packages[$c]
        if ($v) { return Set-BoostRoot $packages[$c].Dir $v }
        Write-Warn 'Automatic install did not work. Falling back to installing it yourself.'
    }

    Write-Host ''
    Write-Host 'To install Boost yourself, download one of these (if one site fails, try the other):'
    foreach ($pkg in $packages) {
        Write-Host "  Boost $($pkg.Version) ($($pkg.Note)):"
        foreach ($u in $pkg.Urls) { Write-Host "    $u" }
    }
    Write-Host "Run it and keep the default location (C:\local\boost_1_XX_0)."
    if (Read-YesNo 'Open the first download link in your browser now?') {
        Start-Process $packages[0].Url
    }

    while ($true) {
        Read-Host 'Press Enter once Boost is installed to pick its folder' | Out-Null
        $p = Select-Folder 'Select your Boost folder (the one containing the "boost" subfolder)' 'C:\local'
        if (-not $p) {
            if (Read-YesNo 'No folder chosen. Try again?') { continue }
            Stop-Wizard 'Boost is required. Run the wizard again once it is installed.'
        }
        $v = Get-BoostVersion $p
        if (-not $v) { Write-Fail "'$p' does not look like a Boost folder (no boost\version.hpp inside)."; continue }
        return Set-BoostRoot $p $v
    }
}

function Resolve-Boost {
    foreach ($root in @($script:Settings.BoostRoot, [Environment]::GetEnvironmentVariable('BOOST_ROOT', 'Machine'))) {
        $v = Get-BoostVersion $root
        if ($v -and $v -ge $MinBoost) {
            if ($root -ne $script:Settings.BoostRoot) { Save-Setting 'BoostRoot' $root }
            Write-Ok "Boost $v at $root"
            return $root
        }
    }
    return Initialize-Boost
}

# ---------------------------------------------------------------------------
# Source code and modules
# ---------------------------------------------------------------------------
function Sync-Repo([string]$Url, [string]$Dir, [string]$Branch) {
    $leaf = Split-Path $Dir -Leaf
    if (Test-Path (Join-Path $Dir '.git')) {
        Write-Step "Updating $leaf..."
        & $script:Git -C $Dir pull --ff-only | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Warn "Could not update $leaf (local changes?). Continuing with the current copy." }
        return
    }
    if ((Test-Path $Dir) -and (Get-ChildItem $Dir -Force | Select-Object -First 1)) {
        throw "'$Dir' exists but is not a git checkout. Move or delete it and re-run."
    }
    Write-Step "Cloning $leaf..."
    $gitArgs = @('clone')
    if ($Branch) { $gitArgs += @('--branch', $Branch) }
    & $script:Git @gitArgs $Url $Dir | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "git clone of $Url failed." }
}

function Select-Modules([bool]$IsFork) {
    $items = @($ModuleCatalog | Where-Object { $IsFork -or -not $_.RequiresFork })
    $selected = @{}
    foreach ($m in $items) { $selected[$m.Name] = [bool]$m.Default }

    while ($true) {
        Write-Host ''
        Write-Host 'Modules to install:'
        for ($i = 0; $i -lt $items.Count; $i++) {
            $mark = if ($selected[$items[$i].Name]) { 'x' } else { ' ' }
            Write-Host ("  {0}) [{1}] {2,-16} {3}" -f ($i + 1), $mark, $items[$i].Name, $items[$i].Desc)
        }
        $a = "$(Read-Host 'Type numbers to toggle (e.g. "3 4"), or press Enter to continue')".Trim()
        if ($a -eq '') { break }
        foreach ($token in ($a -split '[\s,]+')) {
            $n = 0
            if ([int]::TryParse($token, [ref]$n) -and $n -ge 1 -and $n -le $items.Count) {
                $name = $items[$n - 1].Name
                $selected[$name] = -not $selected[$name]
            }
        }
    }
    return @($items | Where-Object { $selected[$_.Name] } | ForEach-Object { $_.Name })
}

# Asks for source/modules/tools once and remembers the answers.
function Resolve-BuildChoices {
    $s = $script:Settings
    # TrinityCore has one source, no modules, and no client data download, so the
    # extractor tools are always built (its guide says to tick "Tools").
    if (-not $script:Core.ClientDataZip) {
        Save-Setting 'SourceIndex' 0
        Save-Setting 'Modules' @()
        Save-Setting 'BuildTools' $true
        Write-Ok "Source: $($Sources[0].Label) (with map extractor tools)"
        return
    }
    if ($null -ne $s.SourceIndex -and $null -ne $s.Modules) {
        $src = $Sources[[int]$s.SourceIndex]
        $mods = if (@($s.Modules).Count) { @($s.Modules) -join ', ' } else { 'none' }
        Write-Host "Previous choices: $($src.Label); modules: $mods; map tools: $($s.BuildTools)"
        if (Read-YesNo 'Keep these choices?') { return }
    }
    $idx = Read-Choice "Which $($script:Core.Name) source do you want?" ($Sources | ForEach-Object { $_.Label })
    Save-Setting 'SourceIndex' $idx
    Save-Setting 'Modules' @(Select-Modules $Sources[$idx].IsFork)
    $opt = $script:Core.ToolsOption
    Save-Setting 'BuildTools' (Read-YesNo "Build the map extractor tools? (The wiki sets $($opt.Name)=$($opt.On). Needed if you extract client data yourself)")
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
function ConvertTo-CMakePath([string]$Path) { return ($Path -replace '\\', '/') }

function Invoke-CMakeConfigure($Paths, $Generator, $BoostRoot, $MySql, [bool]$BuildTools) {
    $opt = $script:Core.ToolsOption
    $tools = if ($BuildTools) { $opt.On } else { $opt.Off }
    $cmakeArgs = @(
        '-S', $Paths.Src, '-B', $Paths.Build,
        '-G', $Generator, '-A', 'x64',
        "-DBOOST_ROOT=$BoostRoot",
        "-DOPENSSL_ROOT_DIR=$(ConvertTo-CMakePath $script:OpenSslRoot)",
        # Forget previously found OpenSSL libraries so a changed install is picked up.
        '-U', 'OPENSSL_*', '-U', 'LIB_EAY*', '-U', 'SSL_EAY*',
        "-DMYSQL_INCLUDE_DIR=$(ConvertTo-CMakePath (Join-Path $MySql.Root 'include'))",
        "-DMYSQL_LIBRARY=$(ConvertTo-CMakePath (Join-Path $MySql.Root 'lib\libmysql.lib'))",
        "-D$($opt.Name)=$tools"
    )
    Write-Step 'Running CMake (configure + generate)...'
    & $script:CMake @cmakeArgs | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed. Scroll up (or check setup-log.txt) for the first error.' }
    Write-Ok 'CMake configuration complete'
}

function Invoke-Build($Paths) {
    Write-Step "Compiling ALL_BUILD ($BuildConfig, x64). This usually takes 15-60 minutes..."
    & $script:CMake --build $Paths.Build --config $BuildConfig --parallel | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed. Scroll up (or check setup-log.txt) for the first "error".' }
    Write-Ok 'Compilation complete'
}

# The wiki's "Required DLLs" table. libmysql.dll must match the MySQL server version,
# so it is always overwritten with the one from the MySQL you selected.
function Copy-RuntimeDlls($Paths, $MySql) {
    if (-not (Test-Path $Paths.Output)) { return }
    $dlls = @()
    $mysqlDll = Join-Path $MySql.Root 'lib\libmysql.dll'
    if (-not (Test-Path $mysqlDll)) { $mysqlDll = Join-Path $MySql.Bin 'libmysql.dll' }
    $dlls += $mysqlDll
    foreach ($name in 'libcrypto-3-x64.dll', 'libssl-3-x64.dll', 'legacy.dll') {
        $found = Get-ChildItem $script:OpenSslRoot -Recurse -Filter $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $dlls += $found.FullName } else { Write-Warn "$name not found under $($script:OpenSslRoot)" }
    }
    foreach ($dll in $dlls) {
        if (Test-Path $dll) {
            Copy-Item $dll $Paths.Output -Force
            Write-Ok "Copied $(Split-Path $dll -Leaf)"
        }
    }
}

# ---------------------------------------------------------------------------
# Client data
# ---------------------------------------------------------------------------
function Test-ClientData([string]$DataDir) {
    return ((Test-Path (Join-Path $DataDir 'dbc')) -and (Test-Path (Join-Path $DataDir 'maps')))
}

function Get-ClientDataZipUrl {
    try {
        $release = Invoke-RestMethod -Uri $script:Core.ClientDataApi -UseBasicParsing
        $asset = $release.assets | Where-Object { $_.name -eq 'Data.zip' } | Select-Object -First 1
        if ($asset) {
            Write-Ok "Latest client data: $($release.name)"
            return $asset.browser_download_url
        }
    } catch { }
    return $script:Core.ClientDataZip
}

function Install-ClientDataDownload($Paths) {
    $url = Get-ClientDataZipUrl
    $zip = Join-Path $Paths.Bin 'Data.zip'
    Write-Step "Downloading $url (about 1.2 GB)..."
    Save-Download $url $zip

    New-Item -ItemType Directory -Force -Path $Paths.Data | Out-Null
    Write-Step "Extracting into $($Paths.Data)..."
    & tar.exe -xf $zip -C $Paths.Data
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'tar.exe failed, falling back to Expand-Archive (slower)...'
        Expand-Archive -Path $zip -DestinationPath $Paths.Data -Force
    }
    # If the zip had its own top-level folder, move its contents up one level.
    if (-not (Test-ClientData $Paths.Data)) {
        $inner = Get-ChildItem $Paths.Data -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'dbc') } | Select-Object -First 1
        if ($inner) {
            Get-ChildItem $inner.FullName | Move-Item -Destination $Paths.Data -Force
            Remove-Item $inner.FullName -Recurse -Force
        }
    }
    if (-not (Test-ClientData $Paths.Data)) { throw "Extraction finished but no dbc/maps folders were found in $($Paths.Data)." }
    Remove-Item $zip -Force
    Write-Ok 'Client data installed'
}

function Resolve-WowDir {
    $saved = $script:Settings.WowDir
    if ($saved -and (Test-Path (Join-Path $saved 'Wow.exe'))) {
        if (Read-YesNo "Use your WoW 3.3.5a client at $saved ?") { return $saved }
    }
    while ($true) {
        $dir = Select-Folder 'Select your WoW 3.3.5a client folder (the one containing Wow.exe)' 'C:\'
        if (-not $dir) { return $null }
        if (Test-Path (Join-Path $dir 'Wow.exe')) { Save-Setting 'WowDir' $dir; return $dir }
        Write-Fail "No Wow.exe in '$dir'."
    }
}

# Run the extractors inside the WoW client folder (AzerothCore option 2; TrinityCore's only option).
function Install-ClientDataExtract($Paths) {
    $files = @($script:Core.Extractors)
    foreach ($t in $files | Where-Object { $_ -like '*.exe' }) {
        if (-not (Test-Path (Join-Path $Paths.Output $t))) {
            throw "$t was not built. Re-run Step 2 and answer yes to building the map extractor tools."
        }
    }
    $wow = Resolve-WowDir
    if (-not $wow) { Stop-Wizard 'No WoW folder chosen.' }

    Write-Step "Copying extractor tools into $wow"
    foreach ($f in $files) {
        $src = Join-Path $Paths.Output $f
        if (Test-Path $src) { Copy-Item $src $wow -Force }
    }
    Copy-Item (Join-Path $Paths.Src $script:Core.ExtractorBat) $wow -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $wow 'mmaps'), (Join-Path $wow 'vmaps') | Out-Null

    Write-Host ''
    Write-Host 'The extractor menu will open in a new window. From the guide:'
    Write-Host '  - dbc, maps AND vmaps are needed for the server to work properly (option 4 does everything)'
    Write-Host '  - mmaps can take hours; do NOT interrupt the vmaps extraction'
    Write-Host '  - finish one task before starting another, then choose EXIT'
    Read-Host 'Press Enter to start the extractor' | Out-Null
    Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', 'extractor.bat' -WorkingDirectory $wow -Wait

    New-Item -ItemType Directory -Force -Path $Paths.Data | Out-Null
    foreach ($folder in 'dbc', 'maps', 'vmaps', 'mmaps', 'Cameras') {
        $src = Join-Path $wow $folder
        if (-not (Test-Path $src) -or -not (Get-ChildItem $src | Select-Object -First 1)) { continue }
        $dest = Join-Path $Paths.Data $folder
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Move-Item $src $dest
        Write-Ok "Moved $folder into Data"
    }
    $buildings = Join-Path $wow 'Buildings'
    if (Test-Path $buildings) { Remove-Item $buildings -Recurse -Force; Write-Ok 'Deleted the temporary Buildings folder' }
    if (-not (Test-ClientData $Paths.Data)) { throw 'dbc and maps are missing. Run the extractor again with option 1 (or 4).' }
}

# Unpacks a .7z. Windows' tar.exe (libarchive) reads 7z on current builds;
# older Windows 10 builds fall back to 7-Zip, installed with winget if needed.
function Expand-7z([string]$Archive, [string]$Destination) {
    & tar.exe -xf $Archive -C $Destination
    if ($LASTEXITCODE -eq 0) { return }
    Write-Warn 'tar.exe could not unpack the .7z, using 7-Zip instead...'
    $7z = Find-Tool '7z' @("$env:ProgramFiles\7-Zip\7z.exe")
    if (-not $7z) {
        Invoke-Winget -Id '7zip.7zip' | Out-Null
        $7z = Find-Tool '7z' @("$env:ProgramFiles\7-Zip\7z.exe")
    }
    if (-not $7z) { throw "Could not unpack $Archive. Install 7-Zip and run the step again." }
    & $7z x $Archive "-o$Destination" -y | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "7-Zip failed to unpack $Archive." }
}

# TrinityCore: the worldserver imports TDB_full_world_*.sql from its own folder
# into an empty world database on first start. The file must keep its name.
function Install-WorldDatabase($Paths) {
    $spec = $script:Core.WorldDbRelease
    $existing = Get-ChildItem $Paths.Bin -Filter $spec.FilePattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) { Write-Ok "World database file present: $($existing.Name)"; return }

    Write-Step 'Looking up the latest TDB (world database) release for 3.3.5...'
    # Assign first: PowerShell 5.1 pipes a JSON array from Invoke-RestMethod as one object.
    $releases = Invoke-RestMethod -Uri $spec.Api -UseBasicParsing
    $release = $releases | Where-Object { $_.tag_name -like "$($spec.TagPrefix)*" } |
               Sort-Object { [datetime]$_.published_at } -Descending | Select-Object -First 1
    $asset = $release.assets | Where-Object { $_.name -like '*.7z' } | Select-Object -First 1
    if (-not $asset) { throw 'Could not find a TDB 335 release on GitHub. Download TDB_full_world_335*.7z from github.com/TrinityCore/TrinityCore/releases into the server folder and unpack it there.' }

    $archive = Join-Path $Paths.Bin $asset.name
    Write-Step "Downloading $($asset.name) ($([math]::Round($asset.size / 1MB)) MB)..."
    Save-Download $asset.browser_download_url $archive
    Expand-7z $archive $Paths.Bin
    Remove-Item $archive -Force
    $sql = Get-ChildItem $Paths.Bin -Filter $spec.FilePattern | Select-Object -First 1
    if (-not $sql) { throw "Unpacked $($asset.name) but found no $($spec.FilePattern) in $($Paths.Bin)." }
    Write-Ok "World database file ready: $($sql.Name) (do not rename it)"
}

# ---------------------------------------------------------------------------
# Servers
# ---------------------------------------------------------------------------
# AzerothCore and TrinityCore both name their programs authserver.exe / worldserver.exe,
# so running servers are told apart by the folder they were started from.
function Get-ServerProcess($Paths, [string[]]$Name, [switch]$Others) {
    $base = $Paths.Base.TrimEnd('\') + '\'
    Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object {
        $mine = $_.Path -and $_.Path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)
        if ($Others) { -not $mine } else { $mine }
    }
}

function Start-ServerProcess($Paths, [string]$Name) {
    if (Get-ServerProcess $Paths $Name) { Write-Ok "$Name is already running"; return }
    # The other core's server uses the same ports (3724 / 8085), so only one can run at a time.
    $other = Get-ServerProcess $Paths $Name -Others | Select-Object -First 1
    if ($other) {
        Write-Warn "Another $Name is running from $(Split-Path $other.Path) and uses the same port."
        if (-not (Read-YesNo 'Stop it so this one can start?' $false)) { Stop-Wizard "Stop the other $Name first, then try again." }
        $other | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
    $exe = Join-Path $Paths.Bin "$Name.exe"
    if (-not (Test-Path $exe)) { throw "$exe not found. Compile first (Step 2)." }
    Start-Process -FilePath $exe -WorkingDirectory $Paths.Bin
    Write-Ok "Started $Name in a new window"
}

function Get-DefaultDbUser {
    if ($script:Settings.DbUser) { return $script:Settings.DbUser }
    return $script:Core.DbUser
}

# Reads the server's database account from authserver.conf (host;port;user;password;database).
function Get-DbAccount($Paths) {
    $info = Get-ConfValue (Join-Path $Paths.Configs 'authserver.conf') 'LoginDatabaseInfo'
    if ($info) {
        $parts = $info -split ';'
        if ($parts.Count -ge 4) { return [pscustomobject]@{ User = $parts[2]; Password = $parts[3] } }
    }
    $user = Read-Text "$($script:Core.Name) database username" (Get-DefaultDbUser)
    return [pscustomobject]@{ User = $user; Password = (Read-Secret "Password for '$user'") }
}

function Wait-ForRealmlist($Account, [int]$TimeoutSeconds = 180) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $r = Invoke-MySql -User $Account.User -Password $Account.Password -Database $script:Core.DbAuth -Sql 'SELECT COUNT(*) FROM realmlist;'
        if ($r.Ok -and [int]("0" + $r.Output) -gt 0) { return $true }
        Start-Sleep -Seconds 5
    }
    return $false
}

# ===========================================================================
# STEP 1: Requirements
# ===========================================================================
function Step-Requirements {
    Write-Header 'Step 1/6: Requirements'
    Install-WingetIfMissing

    # Git's default installer option is the wiki's "Git from the command line and also from 3rd-party software".
    $script:Git = Install-ToolIfMissing 'Git' {
        Find-Tool 'git' @("$env:ProgramFiles\Git\cmd\git.exe")
    } @('Git.Git')

    $script:CMake = Install-ToolIfMissing 'CMake' {
        Find-Tool 'cmake' @("$env:ProgramFiles\CMake\bin\cmake.exe")
    } @('Kitware.CMake')
    if (((& $script:CMake --version) | Out-String) -match '(\d+\.\d+\.\d+)' -and [version]$Matches[1] -lt $MinCMake) {
        Write-Warn "CMake $($Matches[1]) is older than $MinCMake. Upgrading..."
        & winget upgrade --id Kitware.CMake -e --silent --accept-package-agreements --accept-source-agreements | Out-Host
    }

    # The wiki's fix for "missing Microsoft Visual C++" errors; OpenSSL's installer needs it first.
    $vc = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue
    if ($vc -and $vc.Installed -eq 1) { Write-Ok 'Visual C++ Redistributable (x64) found' }
    else { Invoke-Winget -Id 'Microsoft.VCRedist.2015+.x64' | Out-Null }

    # The full Win64 OpenSSL 3.x package (not "Light"), which includes the headers.
    $script:OpenSslRoot = Install-OpenSsl3

    Initialize-VisualStudio | Out-Null

    if (Test-Path "$env:ProgramFiles\HeidiSQL\heidisql.exe") { Write-Ok 'HeidiSQL found' }
    elseif (Read-YesNo 'Install HeidiSQL (a program for browsing/editing the database)?') {
        Invoke-Winget -Id 'HeidiSQL.HeidiSQL' | Out-Null
    }

    Write-Host ''
    Write-Step 'MySQL'
    $script:MySql = $null
    Resolve-MySql | Out-Null

    Write-Host ''
    Write-Step 'Boost'
    Initialize-Boost | Out-Null
}

# ===========================================================================
# STEP 2: Core installation
# ===========================================================================
function Step-CoreInstall {
    Write-Header 'Step 2/6: Core installation'
    Resolve-BuildTools
    $paths = Resolve-Paths
    Resolve-BuildChoices
    $mysql = Resolve-MySql
    $boost = Resolve-Boost
    $generator = Initialize-VisualStudio
    New-Item -ItemType Directory -Force -Path $paths.Base, $paths.Build | Out-Null

    $source = $Sources[[int]$script:Settings.SourceIndex]
    Sync-Repo $source.Url $paths.Src $source.Branch
    foreach ($name in @($script:Settings.Modules)) {
        $mod = $ModuleCatalog | Where-Object { $_.Name -eq $name }
        if ($mod) { Sync-Repo $mod.Url (Join-Path $paths.Src "modules\$name") $null }
    }

    Invoke-CMakeConfigure $paths $generator $boost $mysql ([bool]$script:Settings.BuildTools)

    if (-not (Read-YesNo 'Compile the server now? (Steps 3-5 need the compiled server)')) {
        Write-Host "To compile yourself: open $($paths.Build)\$($script:Core.Solution), pick '$BuildConfig' + 'x64',"
        Write-Host 'then right-click ALL_BUILD > Build. Afterwards run the wizard again and pick Step 2 to copy the DLLs.'
        Stop-Wizard 'Stopped before compiling.'
    }
    Invoke-Build $paths
    Copy-RuntimeDlls $paths $mysql

    # A rebuild only changes the build output; bring the server folder up to date too.
    if ($paths.Published -and (Read-YesNo "Copy the new build into $($paths.Server)? (your .conf settings are kept)")) {
        Publish-Server $paths
    }
}

# ===========================================================================
# STEP 3: Server setup
# ===========================================================================
function Step-ServerSetup {
    Write-Header 'Step 3/6: Server setup'
    $paths = Resolve-Paths
    if (-not (Test-Path (Join-Path $paths.Bin 'worldserver.exe'))) { throw "worldserver.exe not found in $($paths.Bin). Run Step 2 first." }
    if (-not (Test-Path $paths.Configs)) { throw "$($paths.Configs) not found. Rebuild in Step 2." }

    # Copy every *.conf.dist (including AzerothCore module configs) to *.conf, never
    # overwriting existing ones. TrinityCore's sit next to the exes, so don't recurse into Data.
    $recurse = [bool]$script:Core.ConfigsSubdir
    Get-ChildItem $paths.Configs -Recurse:$recurse -Filter '*.conf.dist' | ForEach-Object {
        $conf = $_.FullName -replace '\.dist$', ''
        if (Test-Path $conf) { Write-Ok "$(Split-Path $conf -Leaf) already exists (kept)" }
        else { Copy-Item $_.FullName $conf; Write-Ok "Created $(Split-Path $conf -Leaf)" }
    }

    Write-Host ''
    if (Test-ClientData $paths.Data) {
        Write-Ok "Client data already present in $($paths.Data)"
        $redo = Read-YesNo 'Replace it with a fresh copy?' $false
    } else { $redo = $true }

    if ($redo) {
        $options = @()
        $actions = @()
        if ($script:Core.ClientDataZip) {
            $options += 'Download the pre-extracted data (easiest, enUS clients only, ~1.2 GB)'
            $actions += { Install-ClientDataDownload $paths }
        }
        $options += 'Extract it from my own WoW 3.3.5a client (any language, can take hours)'
        $actions += { Install-ClientDataExtract $paths }
        $options += 'Skip for now'
        $actions += { Write-Warn 'Skipped. The worldserver will not start without client data.' }
        $c = Read-Choice 'How do you want to get the client data (dbc, maps, vmaps, mmaps, cameras)?' $options
        & $actions[$c]
    }

    Set-ConfValue (Join-Path $paths.Configs 'worldserver.conf') 'DataDir' "`"$($paths.Data)`""
    Write-Ok "worldserver.conf: DataDir = $($paths.Data)"
}

# ===========================================================================
# STEP 4: Database setup
# ===========================================================================
function Step-Database {
    Write-Header 'Step 4/6: Database setup'
    $paths = Resolve-Paths
    $mysql = Resolve-MySql
    if ($mysql.Source -eq 'WAMP') { Test-WampService $mysql | Out-Null }

    Write-Host "Use the MySQL root user ONLY to create the $($script:Core.Name) account,"
    Write-Host 'never run the server itself as root.'
    $rootHint = if ($mysql.Source -eq 'WAMP') { ' (WAMP default: empty, just press Enter)' } else { '' }
    $rootPass = $null
    for ($try = 1; $try -le 3; $try++) {
        $rootPass = Read-Secret "MySQL root password$rootHint"
        $r = Invoke-MySql -User 'root' -Password $rootPass -Sql 'SELECT VERSION();'
        if ($r.Ok) { Write-Ok "Logged in to MySQL $($r.Output) as root"; break }
        Write-Fail $r.Output
        $rootPass = $null
    }
    if ($null -eq $rootPass) { Stop-Wizard 'Could not log in as root. Check the password and that MySQL is running.' }

    # --- Server's database account ---
    $coreUser = $script:Core.DbUser
    Write-Host ''
    Write-Host 'Now create the account the server uses to talk to MySQL.'
    Write-Host "The guide's default is $coreUser / $coreUser; choosing your own password is more secure."
    $defaultUser = Get-DefaultDbUser
    do {
        $user = Read-Text 'Database username' $defaultUser
        $validUser = $user -match '^[A-Za-z0-9_]{1,32}$'
        if (-not $validUser) { Write-Warn 'Use only letters, numbers and _ (max 32).' }
    } while (-not $validUser)

    $exists = Invoke-MySql -User 'root' -Password $rootPass -Sql "SELECT COUNT(*) FROM mysql.user WHERE user = $(ConvertTo-SqlString $user) AND host = 'localhost';"
    $setPassword = $true
    if ($exists.Ok -and $exists.Output -eq '1') {
        Write-Warn "MySQL account '$user' already exists."
        $setPassword = Read-YesNo 'Set a new password for it?' $false
    }

    while ($true) {
        if ($setPassword) {
            $pass = Read-Secret "Choose a password for '$user' (press Enter for the default '$coreUser')"
            if ($pass -eq '') { $pass = $coreUser }
            elseif ((Read-Secret 'Type it again') -ne $pass) { Write-Warn 'Passwords did not match.'; continue }
        } else {
            $pass = Read-Secret "Current password for '$user'"
        }
        if ($pass -match '[;"]') { Write-Warn 'The password cannot contain ; or " (they break the .conf format).'; continue }
        break
    }

    $u = ConvertTo-SqlString $user
    $p = ConvertTo-SqlString $pass
    $core = $script:Core
    $databases = @($core.DbWorld, $core.DbCharacters, $core.DbAuth)
    if (@($script:Settings.Modules) -contains 'mod-playerbots') { $databases += 'acore_playerbots' }

    # Same as the project's sql/create/create_mysql.sql, with your username/password.
    $sql = New-Object System.Text.StringBuilder
    [void]$sql.AppendLine("CREATE USER IF NOT EXISTS $u@'localhost' IDENTIFIED BY $p WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0;")
    if ($setPassword) { [void]$sql.AppendLine("ALTER USER $u@'localhost' IDENTIFIED BY $p;") }
    foreach ($db in $databases) {
        [void]$sql.AppendLine("CREATE DATABASE IF NOT EXISTS $db DEFAULT CHARACTER SET UTF8MB4 COLLATE utf8mb4_unicode_ci;")
        [void]$sql.AppendLine("GRANT ALL PRIVILEGES ON $db.* TO $u@'localhost' WITH GRANT OPTION;")
    }
    $r = Invoke-MySql -User 'root' -Password $rootPass -Sql $sql.ToString()
    if (-not $r.Ok) { throw "Creating the account/databases failed: $($r.Output)" }
    Write-Ok "Databases ready: $($databases -join ', ')"

    $check = Invoke-MySql -User $user -Password $pass -Sql 'SELECT 1;'
    if (-not $check.Ok) { throw "Could not log in as '$user': $($check.Output)" }
    Write-Ok "Logged in as '$user'"
    Save-Setting 'DbUser' $user

    # --- Point the configs at the account ---
    $auth  = Join-Path $paths.Configs 'authserver.conf'
    $world = Join-Path $paths.Configs 'worldserver.conf'
    $bots  = Join-Path $paths.Configs 'modules\playerbots.conf'
    if (-not ((Test-Path $auth) -and (Test-Path $world))) {
        Write-Warn 'authserver.conf / worldserver.conf not found yet. Run Step 3, then Step 4 again to fill them in.'
        return
    }
    $prefix = "127.0.0.1;$($mysql.Port);$user;$pass"
    # The server imports SQL with mysql.exe; point it there explicitly (WAMP's is not on PATH by default).
    $mysqlExe = "`"$(Join-Path $mysql.Bin 'mysql.exe')`""
    Set-ConfValue $auth  'LoginDatabaseInfo'     "`"$prefix;$($core.DbAuth)`""
    Set-ConfValue $auth  'MySQLExecutable'       $mysqlExe
    Set-ConfValue $world 'LoginDatabaseInfo'     "`"$prefix;$($core.DbAuth)`""
    Set-ConfValue $world 'WorldDatabaseInfo'     "`"$prefix;$($core.DbWorld)`""
    Set-ConfValue $world 'CharacterDatabaseInfo' "`"$prefix;$($core.DbCharacters)`""
    Set-ConfValue $world 'MySQLExecutable'       $mysqlExe
    if (Test-Path $bots) { Set-ConfValue $bots 'PlayerbotsDatabaseInfo' "`"$prefix;acore_playerbots`"" }
    Write-Ok "Database settings written to the .conf files (port $($mysql.Port))"

    # --- TrinityCore: the world database comes from a TDB release file ---
    if ($core.WorldDbRelease) {
        Write-Host ''
        Install-WorldDatabase $paths
    }

    # --- First start fills the databases (Updates.AutoSetup = 1) ---
    Write-Host ''
    Write-Host 'The servers create all tables automatically the first time they start.'
    Write-Host 'The first worldserver start can take several minutes while it imports the world database.'
    if (Read-YesNo 'Start authserver and worldserver now?') {
        Start-Servers $paths ([pscustomobject]@{ User = $user; Password = $pass })
    }
}

# Starts both servers in the order the core needs. TrinityCore's authserver does not
# create its own database, so the worldserver must run first.
function Start-Servers($Paths, $Account) {
    if ($script:Core.AuthDbCreator -eq 'worldserver') {
        Start-ServerProcess $Paths 'worldserver'
        Write-Step 'Waiting for the worldserver to create the auth database (up to 10 minutes)...'
        if (-not (Wait-ForRealmlist $Account 600)) {
            Write-Warn 'The auth database is not ready yet. Check the worldserver window, then start authserver.exe yourself.'
            return
        }
        Start-ServerProcess $Paths 'authserver'
    } else {
        Start-ServerProcess $Paths 'authserver'
        Start-Sleep -Seconds 3
        Start-ServerProcess $Paths 'worldserver'
    }
}

# ===========================================================================
# STEP 5: Networking
# ===========================================================================
function Get-LanAddresses {
    return @(Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
             ForEach-Object { $_.IPv4Address } | ForEach-Object { $_.IPAddress } |
             Where-Object { $_ -and $_ -notlike '169.254.*' })
}

function Set-FirewallRules($Paths, [string]$Profiles) {
    $authPort  = Get-ConfValue (Join-Path $Paths.Configs 'authserver.conf') 'RealmServerPort'
    $worldPort = Get-ConfValue (Join-Path $Paths.Configs 'worldserver.conf') 'WorldServerPort'
    if (-not $authPort)  { $authPort = 3724 }
    if (-not $worldPort) { $worldPort = 8085 }
    $prefix = $script:Core.Name
    foreach ($rule in @(@{ Name = "$prefix Authserver"; Port = $authPort }, @{ Name = "$prefix Worldserver"; Port = $worldPort })) {
        Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Protocol TCP -LocalPort $rule.Port `
            -Action Allow -Profile ($Profiles -split ',') | Out-Null
        Write-Ok "Firewall: allowed inbound TCP $($rule.Port) ($($rule.Name), profiles: $Profiles)"
    }
    return @($authPort, $worldPort)
}

function Set-ClientRealmlist([string]$Address) {
    $wow = Resolve-WowDir
    if (-not $wow) { return }
    $files = @(Get-ChildItem (Join-Path $wow 'Data') -Directory -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -cmatch '^[a-z]{2}[A-Z]{2}$' } |
               ForEach-Object { Join-Path $_.FullName 'realmlist.wtf' })
    if (-not $files) { $files = @(Join-Path $wow 'realmlist.wtf') }
    foreach ($f in $files) {
        if ((Test-Path $f) -and -not (Test-Path "$f.bak")) { Copy-Item $f "$f.bak" }
        Set-Content -Path $f -Value "set realmlist $Address" -Encoding ASCII
        Write-Ok "Wrote $f"
    }
}

function Step-Networking {
    Write-Header 'Step 5/6: Networking'
    $paths = Resolve-Paths
    Resolve-MySql | Out-Null
    $account = Get-DbAccount $paths

    $mode = Read-Choice 'Who will connect to this server?' @(
        'Only me, on this computer (localhost)',
        'Players on my home network (LAN)',
        'Players over the internet')

    $address = '127.0.0.1'
    if ($mode -eq 1) {
        $lan = Get-LanAddresses
        if ($lan.Count -eq 0) { $address = Read-Text 'LAN IP address of this computer' '192.168.1.2' }
        elseif ($lan.Count -eq 1) { $address = $lan[0] }
        else { $address = $lan[(Read-Choice 'Which network address should players use?' $lan)] }
    } elseif ($mode -eq 2) {
        $c = Read-Choice 'What address will players connect to?' @(
            'My public IP address (detect it automatically via api.ipify.org)',
            'A domain name I own (e.g. mydomain.com)')
        if ($c -eq 0) {
            try { $address = "$(Invoke-RestMethod -Uri 'https://api.ipify.org' -UseBasicParsing)".Trim() }
            catch { $address = Read-Text 'Could not detect it. Your public IP address' '' }
        } else {
            $address = Read-Text 'Domain name' 'mydomain.com'
        }
    }
    Write-Ok "Realm address: $address"

    # --- realmlist table (created in the auth database on the first server start) ---
    $authDb = $script:Core.DbAuth
    $creator = $script:Core.AuthDbCreator
    Write-Step "Updating $authDb.realmlist..."
    $probe = Invoke-MySql -User $account.User -Password $account.Password -Database $authDb -Sql 'SELECT COUNT(*) FROM realmlist;'
    if (-not $probe.Ok -or $probe.Output -eq '0') {
        Write-Warn "The realmlist table does not exist yet (the $creator has not been started once)."
        if (-not (Read-YesNo "Start the $creator now so it can create it?")) { Stop-Wizard "Start $creator.exe once, then run Step 5 again." }
        Start-ServerProcess $paths $creator
        $timeout = if ($creator -eq 'worldserver') { 600 } else { 180 }
        Write-Step "Waiting for the auth database to be created (up to $($timeout / 60) minutes)..."
        if (-not (Wait-ForRealmlist $account $timeout)) { throw "The realmlist table did not appear. Check the $creator window for errors." }
    }
    $r = Invoke-MySql -User $account.User -Password $account.Password -Database $authDb `
        -Sql "UPDATE realmlist SET address = $(ConvertTo-SqlString $address) WHERE id = 1;"
    if (-not $r.Ok) { throw "Updating realmlist failed: $($r.Output)" }
    Write-Ok "realmlist.address = $address"

    # The authserver reads the realm list at startup, so restart it to apply the change.
    $running = Get-ServerProcess $paths 'authserver'
    if ($running -and (Read-YesNo 'Restart the authserver so the new address takes effect?')) {
        $running | Stop-Process -Force
        Start-Sleep -Seconds 2
        Start-ServerProcess $paths 'authserver'
    }

    # --- Firewall ---
    if ($mode -eq 0) {
        Write-Ok 'Localhost only: no firewall changes needed.'
    } else {
        if ($mode -eq 1) {
            $public = @(Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' })
            if ($public.Count -gt 0) {
                Write-Warn "Your network '$($public[0].Name)' is set to Public, which blocks LAN players."
                if (Read-YesNo 'Change it to Private (recommended for a home network)?') {
                    $public | ForEach-Object { Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private }
                    Write-Ok 'Network set to Private'
                }
            }
            $ports = Set-FirewallRules $paths 'Domain,Private'
        } else {
            $ports = Set-FirewallRules $paths 'Any'
            $lan = @(Get-LanAddresses)
            Write-Host ''
            Write-Warn 'Port forwarding must be done on your router; this wizard cannot do that for you.'
            Write-Host "  Forward TCP $($ports[0]) and TCP $($ports[1]) to this computer ($($lan -join ' / '))."
            Write-Host '  Guides for most routers: https://portforward.com'
            Write-Host '  Tip: to share MySQL remotely, use an SSH tunnel instead of opening port 3306.'
        }
    }

    # --- Client realmlist.wtf ---
    Write-Host ''
    Write-Host "Players need this line in their WoW Data\<locale>\realmlist.wtf:  set realmlist $address"
    if (Read-YesNo 'Update realmlist.wtf in a WoW client on this computer?' $false) {
        # On the server's own PC, localhost always works.
        Set-ClientRealmlist $(if ($mode -eq 0) { $address } else { '127.0.0.1' })
    }
}

# ===========================================================================
# Main
# ===========================================================================
# ===========================================================================
# STEP 6: Server folder
# ===========================================================================
# The servers lock their .exe files and the Data folder while running.
function Stop-RunningServers($Paths) {
    $running = @(Get-ServerProcess $Paths 'worldserver', 'authserver')
    if ($running.Count -eq 0) { return }
    Write-Warn "These servers are running: $(($running | ForEach-Object { $_.Name }) -join ', '). They must be stopped first."
    $c = Read-Choice 'How do you want to stop them?' @(
        'I will stop them myself (type "server shutdown 1" in the worldserver window, then close authserver)',
        'Close them now (fine after a test; unsaved character changes from the last few minutes may be lost)')
    if ($c -eq 1) {
        $running | Stop-Process -Force
    } else {
        Write-Step 'Waiting for the servers to stop (up to 5 minutes)...'
        $running | Wait-Process -Timeout 300 -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    if (Get-ServerProcess $Paths 'worldserver', 'authserver') {
        Stop-Wizard 'The servers are still running. Stop them and run Step 6 again.'
    }
    Write-Ok 'Servers stopped'
}

# Copies a finished build into <install folder>\server so the server runs separately
# from the build output. Re-running it (or Step 2 after a rebuild) updates the program
# files but never overwrites the .conf files already in the server folder.
function Publish-Server($Paths) {
    $src = $Paths.Output
    $dst = $Paths.Server
    if (-not (Test-Path (Join-Path $src 'worldserver.exe'))) { throw "No compiled server in $src. Run Step 2 first." }
    Stop-RunningServers $Paths
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    $quiet = @('/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:2', '/W:2')

    # 1) Programs, DLLs, .pdb crash-report files, *.conf.dist, TDB file. Data is moved below.
    Write-Step "Copying server files to $dst..."
    & robocopy.exe $src $dst /E /XD (Join-Path $src 'Data') /XF '*.conf' 'Data.zip' '*.7z' @quiet | Where-Object { "$_".Trim() } | Out-Host
    if ($LASTEXITCODE -ge 8) { throw "Copying the server files failed (robocopy code $LASTEXITCODE)." }

    # 2) .conf files only where the server folder has none yet, so your settings survive updates.
    & robocopy.exe $src $dst '*.conf' /S /XC /XN /XO /XD (Join-Path $src 'Data') @quiet | Where-Object { "$_".Trim() } | Out-Host
    if ($LASTEXITCODE -ge 8) { throw "Copying the .conf files failed (robocopy code $LASTEXITCODE)." }
    Write-Ok 'Server files copied'

    # 3) Client data is several GB, so it is moved (instant on the same drive) instead of copied.
    $srcData = Join-Path $src 'Data'
    $dstData = Join-Path $dst 'Data'
    if (Test-ClientData $dstData) {
        Write-Ok 'Client data already in the server folder'
    } elseif (Test-ClientData $srcData) {
        Write-Step 'Moving client data into the server folder...'
        if (Test-Path $dstData) { Remove-Item $dstData -Recurse -Force }
        Move-Item $srcData $dstData
        Write-Ok "Client data moved to $dstData"
    } else {
        Write-Warn 'No client data found yet. Run Step 3 to add it.'
    }

    # 4) Point the server folder's worldserver.conf at its own Data folder.
    $configs = if ($script:Core.ConfigsSubdir) { Join-Path $dst $script:Core.ConfigsSubdir } else { $dst }
    $worldConf = Join-Path $configs 'worldserver.conf'
    if (Test-Path $worldConf) {
        Set-ConfValue $worldConf 'DataDir' "`"$dstData`""
        Write-Ok "worldserver.conf: DataDir = $dstData"
    } else {
        Write-Warn 'worldserver.conf not found in the server folder yet. Run Step 3 to create it.'
    }

    # From now on Steps 3-5 configure and start the server from this folder.
    $script:Paths = $null
    $null = Resolve-Paths
}

function Step-PublishServer {
    Write-Header 'Step 6/6: Server folder'
    $paths = Resolve-Paths
    Write-Host "This copies the finished server into $($paths.Server), apart from the build files."
    Write-Host 'Do this after the first test start worked. From then on, run the server from that folder.'
    if ($paths.Published) { Write-Host 'The server folder already exists: program files are updated, your .conf files are kept.' }
    if (-not (Read-YesNo 'Continue?')) { return }
    Publish-Server $paths
    Write-Ok "Server ready in $($paths.Server)"
}

function Show-Summary {
    $paths = Resolve-Paths
    Write-Header 'All done!'
    Write-Host "Your server: $($paths.Bin)"
    if ($paths.Published) {
        Write-Host "(The build folder $($paths.Build) is only needed for recompiling. Step 2 updates the server folder after a rebuild.)"
    }
    Write-Host 'To play:'
    Write-Host '  1. Start authserver.exe, then worldserver.exe (both in the folder above)'
    Write-Host '  2. In the worldserver window, create your game account:'
    Write-Host '       account create <name> <password>' -ForegroundColor Gray
    Write-Host '       account set gmlevel <name> 3 -1     (optional: make it a GM)' -ForegroundColor Gray
    Write-Host '  3. Start WoW and log in with that account'
}

function Invoke-FullSetup {
    Step-Requirements
    Step-CoreInstall
    Step-ServerSetup
    Step-Database
    Step-Networking
    Step-PublishServer
    Show-Summary
}

# Loads a core profile into the script variables the steps use, and that core's saved answers.
function Select-Core($Core) {
    $script:Core          = $Core
    $script:DefaultBaseDir = $Core.DefaultBaseDir
    $script:MinMySql      = $Core.MinMySql
    $script:MinBoost      = $Core.MinBoost
    $script:MinCMake      = $Core.MinCMake
    $script:SettingsFile  = Join-Path $PSScriptRoot $Core.SettingsFile
    $script:Sources       = $Core.Sources
    $script:ModuleCatalog = $Core.Modules
    $script:Settings      = @{}
    $script:Paths         = $null
    $script:MySql         = $null
    Import-Settings
}

function Read-CoreChoice {
    Write-Header "$WizardName v$WizardVersion - WoW 3.3.5a server setup"
    $c = Read-Choice 'Which server core do you want to set up?' ($Cores | ForEach-Object { "$($_.Name) - $($_.Tagline)" })
    Select-Core $Cores[$c]
}

function Show-Menu {
    while ($true) {
        $sourceInfo = if ($ModuleCatalog.Count) { 'download source + modules' } else { 'download source' }
        $other = $Cores | Where-Object { $_.Name -ne $script:Core.Name } | Select-Object -First 1
        $actions = @(
            @{ Label = 'Full setup: run every step in order (recommended the first time)'; Run = { Invoke-FullSetup } },
            @{ Label = 'Step 1: Requirements (Git, CMake, OpenSSL, Visual Studio, MySQL, Boost)'; Run = { Step-Requirements } },
            @{ Label = "Step 2: Core installation ($sourceInfo, CMake, compile)"; Run = { Step-CoreInstall } },
            @{ Label = 'Step 3: Server setup (config files, client data)'; Run = { Step-ServerSetup } },
            @{ Label = 'Step 4: Database setup (MySQL account, first start)'; Run = { Step-Database } },
            @{ Label = 'Step 5: Networking (realmlist, firewall)'; Run = { Step-Networking } },
            @{ Label = "Step 6: Server folder (copy the finished server to $(Join-Path $(if ($script:Settings.BaseDir) { $script:Settings.BaseDir } else { $DefaultBaseDir }) 'server'))"; Run = { Step-PublishServer } },
            @{ Label = "Switch to $($other.Name)"; Run = { Select-Core $other } },
            @{ Label = 'Exit'; Run = $null }
        )
        Write-Header "$WizardName v$WizardVersion - $($script:Core.Name) 3.3.5a"
        Write-Host "Log file: $LogFile"
        Write-Host ''
        $c = Read-Choice 'What would you like to do?' ($actions | ForEach-Object { $_.Label })
        if (-not $actions[$c].Run) { return }
        if ($actions[$c].Label -like 'Switch to *') { & $actions[$c].Run; continue }
        try {
            & $actions[$c].Run
        } catch [System.OperationCanceledException] {
            Write-Warn $_.Exception.Message
        } catch {
            Write-Fail $_.Exception.Message
            Write-Host "Details were saved to $LogFile" -ForegroundColor Yellow
        }
        Read-Host 'Press Enter to return to the menu' | Out-Null
    }
}

# Only run when executed directly, so the functions can be dot-sourced for testing.
if ($MyInvocation.InvocationName -ne '.') {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Requesting administrator rights...' -ForegroundColor Yellow
        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        } catch {
            Write-Host 'Administrator rights are required. Right-click Start-Setup.bat and choose "Run as administrator".' -ForegroundColor Red
            Read-Host 'Press Enter to close' | Out-Null
        }
        exit
    }

    Start-Transcript -Path $LogFile -Append | Out-Null
    # Recorded in setup-log.txt so bug reports show which version was run.
    Write-Host "$WizardName v$WizardVersion on $([Environment]::OSVersion.VersionString), PowerShell $($PSVersionTable.PSVersion)"
    try {
        Read-CoreChoice
        Show-Menu
    } finally {
        Stop-Transcript | Out-Null
    }
}
