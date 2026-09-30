#Requires -Version 5.1
<#
.SYNOPSIS
    Interactive setup wizard for AzerothCore 3.3.5a on Windows.

.DESCRIPTION
    Follows the official AzerothCore wiki guides, in order:
      Step 1  Requirements        https://www.azerothcore.org/wiki/windows-requirements
      Step 2  Core installation   https://www.azerothcore.org/wiki/windows-core-installation
      Step 3  Server setup        https://www.azerothcore.org/wiki/windows-server-setup
      Step 4  Database setup      https://www.azerothcore.org/wiki/database-installation
      Step 5  Networking          https://www.azerothcore.org/wiki/networking

    Run everything at once, or pick a single step from the menu. Every step
    checks what is already done first, so it is safe to re-run. Answers are
    remembered in wizard-settings.json (passwords are never saved there).

    Start it with Start-Setup.bat (double-click), or:
        powershell -ExecutionPolicy Bypass -File .\AzerothCore-Setup.ps1
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# Settings (minimum versions are from the wiki's Windows requirements page)
# ---------------------------------------------------------------------------
$DefaultBaseDir = 'C:\AzerothCore'
$MinMySql       = [version]'8.0.0'
$MinBoost       = [version]'1.78.0'
$MinCMake       = [version]'3.16.0'
$BuildConfig    = 'RelWithDebInfo'
$ClientDataApi  = 'https://api.github.com/repos/wowgaming/client-data/releases/latest'
$ClientDataZip  = 'https://github.com/wowgaming/client-data/releases/download/v20.0/Data.zip'
$BoostUrl       = 'https://sourceforge.net/projects/boost/files/boost-binaries/1.78.0/boost_1_78_0-msvc-14.3-64.exe/download'
$BoostDir       = 'C:\local\boost_1_78_0'
$LogFile        = Join-Path $PSScriptRoot 'setup-log.txt'
$SettingsFile   = Join-Path $PSScriptRoot 'wizard-settings.json'

$Sources = @(
    @{ Label = 'Playerbots fork (required if you want bots)'; Url = 'https://github.com/mod-playerbots/azerothcore-wotlk.git'; Branch = 'Playerbot'; IsFork = $true },
    @{ Label = 'Stock AzerothCore';                            Url = 'https://github.com/azerothcore/azerothcore-wotlk.git';    Branch = 'master';    IsFork = $false }
)

$ModuleCatalog = @(
    @{ Name = 'mod-playerbots';  Url = 'https://github.com/mod-playerbots/mod-playerbots.git'; Desc = 'AI player bots (Playerbots fork only)'; RequiresFork = $true;  Default = $true  },
    @{ Name = 'mod-autobalance'; Url = 'https://github.com/azerothcore/mod-autobalance.git';   Desc = 'Scales dungeons/raids to group size';   RequiresFork = $false; Default = $true  },
    @{ Name = 'mod-solo-lfg';    Url = 'https://github.com/azerothcore/mod-solo-lfg.git';      Desc = 'Queue for dungeons solo';               RequiresFork = $false; Default = $false },
    @{ Name = 'mod-transmog';    Url = 'https://github.com/azerothcore/mod-transmog.git';      Desc = 'Transmogrification NPC';                RequiresFork = $false; Default = $false },
    @{ Name = 'mod-ah-bot';      Url = 'https://github.com/azerothcore/mod-ah-bot.git';        Desc = 'Fills the auction house';               RequiresFork = $false; Default = $false }
)

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

# Downloads with curl.exe (ships with Windows 10+): shows progress, resumes a
# partial file, and skips the download if the file is already complete.
function Save-Download([string]$Url, [string]$OutFile) {
    if (Test-Path $OutFile) {
        $head = (& curl.exe -sIL $Url) | Out-String
        $sizes = [regex]::Matches($head, '(?im)^content-length:\s*(\d+)')
        if ($sizes.Count -gt 0 -and [int64]$sizes[$sizes.Count - 1].Groups[1].Value -eq (Get-Item $OutFile).Length) {
            Write-Ok "$(Split-Path $OutFile -Leaf) already downloaded"
            return
        }
    }
    & curl.exe -L --fail -C - -o $OutFile $Url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url (run the step again to resume)" }
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

function Find-OpenSsl {
    foreach ($root in @((Join-Path $env:ProgramFiles 'OpenSSL-Win64'), 'C:\OpenSSL-Win64')) {
        if (Test-Path (Join-Path $root 'include\openssl\ssl.h')) { return $root }
    }
    return $null
}

function Resolve-BuildTools {
    if (-not $script:Git)   { $script:Git   = Find-Tool 'git'   @("$env:ProgramFiles\Git\cmd\git.exe") }
    if (-not $script:CMake) { $script:CMake = Find-Tool 'cmake' @("$env:ProgramFiles\CMake\bin\cmake.exe") }
    if (-not $script:OpenSslRoot) { $script:OpenSslRoot = Find-OpenSsl }
    if (-not ($script:Git -and $script:CMake -and $script:OpenSslRoot)) {
        throw 'Git, CMake or OpenSSL is missing. Run Step 1 (Requirements) first.'
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
        if (-not (Read-YesNo "Install AzerothCore into $base ?")) {
            $base = Select-Folder 'Choose where to install AzerothCore' 'C:\'
            if (-not $base) { Stop-Wizard 'No install folder chosen.' }
        }
        if ($base -like '*OneDrive*') { Write-Warn 'Building inside OneDrive is slow and can break. A plain folder like C:\AzerothCore is better.' }
        Save-Setting 'BaseDir' $base
    }
    $build = Join-Path $base 'build'
    $bin = Join-Path $build "bin\$BuildConfig"
    $script:Paths = [pscustomobject]@{
        Base    = $base
        Src     = (Join-Path $base 'azerothcore-wotlk')
        Build   = $build
        Bin     = $bin
        Configs = (Join-Path $bin 'configs')
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
    $range = '[17.0,)'   # 2022 or newer; the wiki says no previews, which vswhere skips by default

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
        if (-not $vs) { throw 'Visual Studio installation failed. Install Visual Studio 2022 with "Desktop development with C++" manually.' }
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

# AzerothCore supports the 8.x line only (the wiki: "MySQL 26.x.x is not supported. Use MySQL 8.4 LTS").
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
        Write-Fail 'WAMP has no MySQL versions installed (MariaDB is not supported by AzerothCore).'
        return $null
    }

    Write-Host ''
    Write-Host 'MySQL versions found in WAMP:'
    foreach ($i in $installs) {
        $status = if (-not (Test-MySqlVersionOk $i.Version)) { 'unsupported, need 8.x (8.4 recommended)' }
                  elseif (-not $i.HasDevFiles) { 'missing include\ or lib\ files' }
                  else { 'OK' }
        Write-Host ("  {0,-20} version {1,-9} port {2,-6} {3}" -f $i.Name, $i.Version, $i.Port, $status)
    }

    $good = @($installs | Where-Object { (Test-MySqlVersionOk $_.Version) -and $_.HasDevFiles } | Sort-Object Version -Descending)
    if ($good.Count -eq 0) { return $null }

    $pick = $good[0]
    if ($good.Count -gt 1) {
        $idx = Read-Choice 'Which MySQL should AzerothCore use?' ($good | ForEach-Object { "$($_.Name) (port $($_.Port))" })
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
        Write-Warn 'AzerothCore needs MySQL 8.x (8.4 recommended). You can add a MySQL 8.4 addon to WAMP from wampserver.aviatechno.net.'
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
    Write-Ok "BOOST_ROOT = $normalized"
    return $normalized
}

# Downloads the prebuilt Boost 1.78 (MSVC 14.3, 64-bit) and runs its Inno Setup
# installer silently. Returns the installed version, or $null on failure.
function Install-Boost {
    $exe = Join-Path $env:TEMP 'boost_1_78_0-msvc-14.3-64.exe'
    Write-Step 'Downloading Boost 1.78...'
    Save-Download $BoostUrl $exe
    Write-Step "Installing Boost into $BoostDir (unpacking takes a few minutes)..."
    $proc = Start-Process -FilePath $exe -Wait -PassThru -ArgumentList @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$BoostDir`"")
    if ($proc.ExitCode -ne 0) { Write-Fail "Boost installer exited with code $($proc.ExitCode)"; return $null }
    $v = Get-BoostVersion $BoostDir
    if ($v) {
        Remove-Item $exe -Force -ErrorAction SilentlyContinue
        Write-Ok "Boost $v installed"
    }
    return $v
}

function Initialize-Boost {
    $candidates = @($env:BOOST_ROOT, [Environment]::GetEnvironmentVariable('BOOST_ROOT', 'Machine'))
    $candidates += @(Get-ChildItem 'C:\local' -Directory -Filter 'boost_*' -ErrorAction SilentlyContinue |
                     Sort-Object Name -Descending | ForEach-Object { $_.FullName })

    foreach ($c in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        $v = Get-BoostVersion $c
        if ($v) {
            Write-Ok "Found Boost $v at $c"
            if (Read-YesNo 'Use this Boost?') { return Set-BoostRoot $c $v }
        }
    }

    Write-Host ''
    Write-Host 'Boost was not found.'
    $c = Read-Choice 'How do you want to install it?' @(
        "Download and install Boost 1.78 for Visual Studio 2022 automatically (~180 MB, into $BoostDir)",
        'I will download and install it myself')
    if ($c -eq 0) {
        $v = Install-Boost
        if ($v) { return Set-BoostRoot $BoostDir $v }
        Write-Warn 'Automatic install did not work. Falling back to installing it yourself.'
    }

    Write-Host ''
    Write-Host 'To install Boost yourself:'
    Write-Host '  1. Download boost_1_78_0-msvc-14.3-64.exe (the link opens in your browser)'
    Write-Host "  2. Run it and keep the default location ($BoostDir)"
    if (Read-YesNo 'Open the download link in your browser now?') {
        Start-Process $BoostUrl
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
    $root = [Environment]::GetEnvironmentVariable('BOOST_ROOT', 'Machine')
    $v = Get-BoostVersion $root
    if ($v) { Write-Ok "Boost $v at $root"; return $root }
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
    if ($null -ne $s.SourceIndex -and $null -ne $s.Modules) {
        $src = $Sources[[int]$s.SourceIndex]
        $mods = if (@($s.Modules).Count) { @($s.Modules) -join ', ' } else { 'none' }
        Write-Host "Previous choices: $($src.Label); modules: $mods; map tools: $($s.BuildTools)"
        if (Read-YesNo 'Keep these choices?') { return }
    }
    $idx = Read-Choice 'Which AzerothCore source do you want?' ($Sources | ForEach-Object { $_.Label })
    Save-Setting 'SourceIndex' $idx
    Save-Setting 'Modules' @(Select-Modules $Sources[$idx].IsFork)
    Save-Setting 'BuildTools' (Read-YesNo 'Build the map extractor tools? (The wiki sets TOOLS_BUILD=all. Needed if you extract client data yourself)')
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
function ConvertTo-CMakePath([string]$Path) { return ($Path -replace '\\', '/') }

function Invoke-CMakeConfigure($Paths, $Generator, $BoostRoot, $MySql, [bool]$BuildTools) {
    $tools = if ($BuildTools) { 'all' } else { 'none' }
    $cmakeArgs = @(
        '-S', $Paths.Src, '-B', $Paths.Build,
        '-G', $Generator, '-A', 'x64',
        "-DBOOST_ROOT=$BoostRoot",
        "-DOPENSSL_ROOT_DIR=$(ConvertTo-CMakePath $script:OpenSslRoot)",
        "-DMYSQL_INCLUDE_DIR=$(ConvertTo-CMakePath (Join-Path $MySql.Root 'include'))",
        "-DMYSQL_LIBRARY=$(ConvertTo-CMakePath (Join-Path $MySql.Root 'lib\libmysql.lib'))",
        "-DTOOLS_BUILD=$tools"
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
    if (-not (Test-Path $Paths.Bin)) { return }
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
            Copy-Item $dll $Paths.Bin -Force
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
        $release = Invoke-RestMethod -Uri $ClientDataApi -UseBasicParsing
        $asset = $release.assets | Where-Object { $_.name -eq 'Data.zip' } | Select-Object -First 1
        if ($asset) {
            Write-Ok "Latest client data: $($release.name)"
            return $asset.browser_download_url
        }
    } catch { }
    return $ClientDataZip
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

# Option 2 from the wiki: run the extractors inside the WoW client folder.
function Install-ClientDataExtract($Paths) {
    $tools = 'map_extractor.exe', 'mmaps_generator.exe', 'vmap4_extractor.exe', 'vmap4_assembler.exe'
    foreach ($t in $tools) {
        if (-not (Test-Path (Join-Path $Paths.Bin $t))) {
            throw "$t was not built. Re-run Step 2 and answer yes to building the map extractor tools."
        }
    }
    $wow = Resolve-WowDir
    if (-not $wow) { Stop-Wizard 'No WoW folder chosen.' }

    Write-Step "Copying extractor tools into $wow"
    foreach ($f in $tools + 'mmaps-config.yaml') {
        $src = Join-Path $Paths.Bin $f
        if (Test-Path $src) { Copy-Item $src $wow -Force }
    }
    Copy-Item (Join-Path $Paths.Src 'apps\extractor\extractor.bat') $wow -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $wow 'mmaps'), (Join-Path $wow 'vmaps') | Out-Null

    Write-Host ''
    Write-Host 'The extractor menu will open in a new window. From the wiki:'
    Write-Host '  - dbc, maps AND vmaps are needed for the server to work properly (option 4 does everything)'
    Write-Host '  - mmaps can take hours; do NOT interrupt the vmaps extraction'
    Write-Host '  - finish one task before starting another, then choose 5 to exit'
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

# ---------------------------------------------------------------------------
# Servers
# ---------------------------------------------------------------------------
function Start-ServerProcess($Paths, [string]$Name) {
    if (Get-Process -Name $Name -ErrorAction SilentlyContinue) { Write-Ok "$Name is already running"; return }
    $exe = Join-Path $Paths.Bin "$Name.exe"
    if (-not (Test-Path $exe)) { throw "$exe not found. Compile first (Step 2)." }
    Start-Process -FilePath $exe -WorkingDirectory $Paths.Bin
    Write-Ok "Started $Name in a new window"
}

# Reads the acore account from authserver.conf (host;port;user;password;database).
function Get-DbAccount($Paths) {
    $info = Get-ConfValue (Join-Path $Paths.Configs 'authserver.conf') 'LoginDatabaseInfo'
    if ($info) {
        $parts = $info -split ';'
        if ($parts.Count -ge 4) { return [pscustomobject]@{ User = $parts[2]; Password = $parts[3] } }
    }
    $user = Read-Text 'AzerothCore database username' $(if ($script:Settings.DbUser) { $script:Settings.DbUser } else { 'acore' })
    return [pscustomobject]@{ User = $user; Password = (Read-Secret "Password for '$user'") }
}

function Wait-ForRealmlist($Account, [int]$TimeoutSeconds = 180) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $r = Invoke-MySql -User $Account.User -Password $Account.Password -Database 'acore_auth' -Sql 'SELECT COUNT(*) FROM realmlist;'
        if ($r.Ok -and [int]("0" + $r.Output) -gt 0) { return $true }
        Start-Sleep -Seconds 5
    }
    return $false
}

# ===========================================================================
# STEP 1: Requirements
# ===========================================================================
function Step-Requirements {
    Write-Header 'Step 1/5: Requirements'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Fail 'winget was not found. Install "App Installer" from the Microsoft Store, then re-run.'
        Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1'
        Stop-Wizard 'winget is required.'
    }
    Write-Ok 'winget available'

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

    # The full Win64 OpenSSL 3.x package (not "Light"), which includes the headers.
    $script:OpenSslRoot = Install-ToolIfMissing 'OpenSSL 3 (Win64, full)' { Find-OpenSsl } @('ShiningLight.OpenSSL.Dev', 'ShiningLight.OpenSSL')

    # The wiki's fix for "missing Microsoft Visual C++" errors from OpenSSL.
    $vc = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue
    if ($vc -and $vc.Installed -eq 1) { Write-Ok 'Visual C++ Redistributable (x64) found' }
    else { Invoke-Winget -Id 'Microsoft.VCRedist.2015+.x64' | Out-Null }

    Initialize-VisualStudio | Out-Null

    if (Test-Path "$env:ProgramFiles\HeidiSQL\heidisql.exe") { Write-Ok 'HeidiSQL found' }
    elseif (Read-YesNo 'Install HeidiSQL (a program for browsing/editing the database)?') {
        Invoke-Winget -Id 'AnsgarBecker.HeidiSQL' | Out-Null
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
    Write-Header 'Step 2/5: Core installation'
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
        Write-Host "To compile yourself: open $($paths.Build)\AzerothCore.sln, pick '$BuildConfig' + 'x64',"
        Write-Host 'then right-click ALL_BUILD > Build. Afterwards run the wizard again and pick Step 2 to copy the DLLs.'
        Stop-Wizard 'Stopped before compiling.'
    }
    Invoke-Build $paths
    Copy-RuntimeDlls $paths $mysql
}

# ===========================================================================
# STEP 3: Server setup
# ===========================================================================
function Step-ServerSetup {
    Write-Header 'Step 3/5: Server setup'
    $paths = Resolve-Paths
    if (-not (Test-Path (Join-Path $paths.Bin 'worldserver.exe'))) { throw "worldserver.exe not found in $($paths.Bin). Run Step 2 first." }
    if (-not (Test-Path $paths.Configs)) { throw "$($paths.Configs) not found. Rebuild in Step 2." }

    # Copy every *.conf.dist (including module configs) to *.conf, never overwriting existing ones.
    Get-ChildItem $paths.Configs -Recurse -Filter '*.conf.dist' | ForEach-Object {
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
        $c = Read-Choice 'How do you want to get the client data (dbc, maps, vmaps, mmaps, cameras)?' @(
            'Download the pre-extracted data (easiest, enUS clients only, ~1.2 GB)',
            'Extract it from my own WoW 3.3.5a client (needed for non-enUS clients, can take hours)',
            'Skip for now')
        switch ($c) {
            0 { Install-ClientDataDownload $paths }
            1 { Install-ClientDataExtract $paths }
            2 { Write-Warn 'Skipped. The worldserver will not start without client data.' }
        }
    }

    Set-ConfValue (Join-Path $paths.Configs 'worldserver.conf') 'DataDir' "`"$($paths.Data)`""
    Write-Ok "worldserver.conf: DataDir = $($paths.Data)"
}

# ===========================================================================
# STEP 4: Database setup
# ===========================================================================
function Step-Database {
    Write-Header 'Step 4/5: Database setup'
    $paths = Resolve-Paths
    $mysql = Resolve-MySql
    if ($mysql.Source -eq 'WAMP') { Test-WampService $mysql | Out-Null }

    Write-Host 'The wiki: use the MySQL root user ONLY to create the AzerothCore account,'
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

    # --- AzerothCore account ---
    Write-Host ''
    Write-Host 'Now create the account the server uses to talk to MySQL.'
    Write-Host "The wiki's default is acore / acore; choosing your own password is more secure."
    $defaultUser = if ($script:Settings.DbUser) { $script:Settings.DbUser } else { 'acore' }
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
            $pass = Read-Secret "Choose a password for '$user' (press Enter for the default 'acore')"
            if ($pass -eq '') { $pass = 'acore' }
            elseif ((Read-Secret 'Type it again') -ne $pass) { Write-Warn 'Passwords did not match.'; continue }
        } else {
            $pass = Read-Secret "Current password for '$user'"
        }
        if ($pass -match '[;"]') { Write-Warn 'The password cannot contain ; or " (they break the .conf format).'; continue }
        break
    }

    $u = ConvertTo-SqlString $user
    $p = ConvertTo-SqlString $pass
    $databases = @('acore_world', 'acore_characters', 'acore_auth')
    if (@($script:Settings.Modules) -contains 'mod-playerbots') { $databases += 'acore_playerbots' }

    # Same as data/sql/create/create_mysql.sql, with your username/password.
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
    Set-ConfValue $auth  'LoginDatabaseInfo'     "`"$prefix;acore_auth`""
    Set-ConfValue $auth  'MySQLExecutable'       $mysqlExe
    Set-ConfValue $world 'LoginDatabaseInfo'     "`"$prefix;acore_auth`""
    Set-ConfValue $world 'WorldDatabaseInfo'     "`"$prefix;acore_world`""
    Set-ConfValue $world 'CharacterDatabaseInfo' "`"$prefix;acore_characters`""
    Set-ConfValue $world 'MySQLExecutable'       $mysqlExe
    if (Test-Path $bots) { Set-ConfValue $bots 'PlayerbotsDatabaseInfo' "`"$prefix;acore_playerbots`"" }
    Write-Ok "Database settings written to the .conf files (port $($mysql.Port))"

    # --- First start fills the databases (Updates.AutoSetup = 1) ---
    Write-Host ''
    Write-Host 'The servers create all tables automatically the first time they start.'
    Write-Host 'The first worldserver start can take several minutes while it imports the world database.'
    if (Read-YesNo 'Start authserver and worldserver now?') {
        Start-ServerProcess $paths 'authserver'
        Start-Sleep -Seconds 3
        Start-ServerProcess $paths 'worldserver'
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
    foreach ($rule in @(@{ Name = 'AzerothCore Authserver'; Port = $authPort }, @{ Name = 'AzerothCore Worldserver'; Port = $worldPort })) {
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
    Write-Header 'Step 5/5: Networking'
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

    # --- realmlist table (acore_auth is created on the authserver's first start) ---
    Write-Step 'Updating acore_auth.realmlist...'
    $probe = Invoke-MySql -User $account.User -Password $account.Password -Database 'acore_auth' -Sql 'SELECT COUNT(*) FROM realmlist;'
    if (-not $probe.Ok -or $probe.Output -eq '0') {
        Write-Warn 'The realmlist table does not exist yet (the authserver has not been started once).'
        if (-not (Read-YesNo 'Start the authserver now so it can create it?')) { Stop-Wizard 'Start authserver.exe once, then run Step 5 again.' }
        Start-ServerProcess $paths 'authserver'
        Write-Step 'Waiting for the auth database to be created (up to 3 minutes)...'
        if (-not (Wait-ForRealmlist $account)) { throw 'The realmlist table did not appear. Check the authserver window for errors.' }
    }
    $r = Invoke-MySql -User $account.User -Password $account.Password -Database 'acore_auth' `
        -Sql "UPDATE realmlist SET address = $(ConvertTo-SqlString $address) WHERE id = 1;"
    if (-not $r.Ok) { throw "Updating realmlist failed: $($r.Output)" }
    Write-Ok "realmlist.address = $address"

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
function Show-Summary {
    $paths = Resolve-Paths
    Write-Header 'All done!'
    Write-Host "Server files: $($paths.Bin)"
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
    Show-Summary
}

function Show-Menu {
    $actions = @(
        @{ Label = 'Full setup: run every step in order (recommended the first time)'; Run = { Invoke-FullSetup } },
        @{ Label = 'Step 1: Requirements (Git, CMake, OpenSSL, Visual Studio, MySQL, Boost)'; Run = { Step-Requirements } },
        @{ Label = 'Step 2: Core installation (download source + modules, CMake, compile)'; Run = { Step-CoreInstall } },
        @{ Label = 'Step 3: Server setup (config files, client data)'; Run = { Step-ServerSetup } },
        @{ Label = 'Step 4: Database setup (MySQL account, first start)'; Run = { Step-Database } },
        @{ Label = 'Step 5: Networking (realmlist, firewall)'; Run = { Step-Networking } },
        @{ Label = 'Exit'; Run = $null }
    )
    while ($true) {
        Write-Header 'AzerothCore 3.3.5a Setup Wizard'
        Write-Host "Log file: $LogFile"
        Write-Host ''
        $c = Read-Choice 'What would you like to do?' ($actions | ForEach-Object { $_.Label })
        if (-not $actions[$c].Run) { return }
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
    try {
        Import-Settings
        Show-Menu
    } finally {
        Stop-Transcript | Out-Null
    }
}
