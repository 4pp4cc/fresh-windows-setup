#requires -Version 5.1
<#
Manual post-install setup for Windows 11 x64. Run in Windows PowerShell as
administrator under the account whose desktop should be configured.
No disk formatting or automatic reboot is performed.
Keep this file beside Start-Setup.bat and double-click the BAT to launch.
After verifying a restore point, it runs tweaks, apps, Office and drivers in four
visible terminals. Run the same BAT again after Windows updates to reapply
tweaks/remove returned bloatware and update apps. Existing Office is updated,
not reinstalled. Close Office apps for updates and reboot only after all workers
and vendor installers finish. Reports are under ProgramData\FreshWindowsSetup.
#>
[CmdletBinding()]
param(
    [switch]$SkipDebloat,
    [switch]$SkipOffice,
    [switch]$SkipGpu,
    [switch]$SkipApps,
    [switch]$SkipNetTime,
    [switch]$SkipDrivers,
    [switch]$SkipFinalCommand,
    [ValidateSet('Coordinator','Apps','Office','Drivers')][string]$Worker = 'Coordinator',
    [string]$RunRoot
)

$ErrorActionPreference = 'Stop'
$script:SetupParameters = $PSBoundParameters
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Use Windows PowerShell 5.1 (powershell.exe), not PowerShell 7.'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open Windows PowerShell as administrator, then run this script again.'
}
$os = Get-CimInstance Win32_OperatingSystem
if ([int]$os.BuildNumber -lt 22000 -or -not [Environment]::Is64BitProcess -or
    $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'This script targets Windows 11 on an x64 PC.'
}
# Reject elevation under a different account: HKCU would configure the wrong desktop.
$sessionId = (Get-Process -Id $PID).SessionId
$shell = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" |
    Where-Object { $_.SessionId -eq $sessionId } | Select-Object -First 1
if (-not $shell) { throw 'Run this script from your signed-in Windows desktop.' }
$owner = Invoke-CimMethod -InputObject $shell -MethodName GetOwnerSid
if ($owner.Sid -ne $identity.User.Value) {
    throw 'Run elevated as the same user who is signed into this desktop.'
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if ($Worker -eq 'Coordinator') {
    $script:RunMutex = New-Object Threading.Mutex($false, 'Local\FreshWindowsSetupCoordinator')
    try { $locked = $script:RunMutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'Another setup run is active. Wait for all its terminals to finish.' }
    $runDir = Join-Path $env:ProgramData ('FreshWindowsSetup\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID)
} else {
    if (-not $RunRoot -or -not (Test-Path -LiteralPath (Join-Path $RunRoot 'restore-ready.txt'))) {
        throw 'Worker must be launched by the coordinator after the restore-point step.'
    }
    $runDir = $RunRoot
}
$Host.UI.RawUI.WindowTitle = "Fresh Windows Setup - $Worker"
$script:Workers = @()
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$script:Results = New-Object 'System.Collections.Generic.List[object]'
Start-Transcript -Path (Join-Path $runDir ('setup-' + $Worker + '.log')) | Out-Null

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    try {
        & $Action
        $script:Results.Add([pscustomobject]@{Step=$Name; Status='Completed'; Detail=''})
    } catch {
        Write-Warning "$Name : $($_.Exception.Message)"
        $script:Results.Add([pscustomobject]@{Step=$Name; Status='Needs attention'; Detail=$_.Exception.Message})
    }
}

function Get-Download {
    param([string]$Url, [string]$Destination, [string]$Sha256, [string]$Publisher,
        [switch]$AllowGpuSignatureFailure)
    if (([uri]$Url).Scheme -ne 'https') { throw 'Only HTTPS downloads are accepted.' }
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination
    $hash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    Write-Host "Downloaded $(Split-Path $Destination -Leaf), SHA256: $hash"
    if ($Sha256 -and $hash -ne $Sha256) { throw "Checksum mismatch: $Destination" }
    if ($Publisher) {
        $sig = Get-AuthenticodeSignature -LiteralPath $Destination
        Write-Host "Signature status: $($sig.Status); signer: $($sig.SignerCertificate.Subject)"
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch $Publisher) {
            $trustedGpuHost = ([uri]$Url).Host -match '^(drivers\.amd\.com|(?:us|international)\.download\.nvidia\.com)$'
            if (-not $AllowGpuSignatureFailure -or -not $trustedGpuHost) {
                throw "Publisher/signature verification failed: $Destination ($($sig.Status))"
            }
            $stream = [IO.File]::OpenRead($Destination)
            try { $isExecutable = $stream.ReadByte() -eq 77 -and $stream.ReadByte() -eq 90 }
            finally { $stream.Dispose() }
            if (-not $isExecutable) { throw 'GPU download is not a Windows executable.' }
            Write-Warning 'Continuing with the official GPU download as requested, despite its signature-check failure.'
        }
    }
}

function Invoke-Installer {
    param([string]$Path, [string]$Arguments = '', [int]$TimeoutMinutes = 90)
    # These are foreground installers; vendor dialogs are deliberately visible.
    $start = @{FilePath=$Path; PassThru=$true}
    if ($Arguments) { $start.ArgumentList = $Arguments }
    for ($attempt = 1; $attempt -le 6; $attempt++) {
    $process = Start-Process @start
    if (-not $process.WaitForExit($TimeoutMinutes * 60000)) {
        throw 'Installer is still running. Finish it before re-running this step.'
    }
    $process.Refresh()
    if ($process.ExitCode -eq 1618 -and $attempt -lt 6) {
        Write-Host 'Windows Installer is busy in another terminal. Retrying in 20 seconds.'
        Start-Sleep -Seconds 20
        continue
    }
    if ($process.ExitCode -notin @(0, 3010, 1641)) {
        throw "Installer returned exit code $($process.ExitCode)."
    }
    if ($process.ExitCode -in @(3010,1641)) { Write-Warning 'Installer requests a restart.' }
    break
    }
}

function Set-Dword {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
    if ((Get-ItemPropertyValue -LiteralPath $Path -Name $Name) -ne $Value) {
        throw "Registry setting did not stick: $Path / $Name"
    }
}

function Initialize-ShellRefresh {
    if ('FreshWindowsSetup.ShellSettings' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace FreshWindowsSetup {
    public static class ShellSettings {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, UIntPtr wParam,
            string lParam, uint flags, uint timeout, out UIntPtr result);
        [DllImport("powrprof.dll")]
        public static extern uint PowerSetActiveOverlayScheme(ref Guid scheme);
    }
}
'@
}

function Set-PowerProfile {
    Write-Host "`nChoose the final power profile:"
    Write-Host '1) Display off after 5 min; sleep after 1 hour; lid close = sleep.'
    Write-Host '2) Display off after 5 min; never sleep automatically; lid close = do nothing.'
    Write-Host 'Both apply performance settings on mains power and battery.'
    do { $choice = Read-Host 'Choose 1 or 2' } until ($choice -in @('1','2'))
    $sleepMinutes = if ($choice -eq '1') { 60 } else { 0 }
    $lidAction = if ($choice -eq '1') { 1 } else { 0 }
    & powercfg.exe /setactive SCHEME_MIN
    if ($LASTEXITCODE -ne 0) {
        $output = & powercfg.exe /duplicatescheme SCHEME_MIN 2>&1
        $guid = [regex]::Match(($output -join ' '), '[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}').Value
        if ($guid) { & powercfg.exe /setactive $guid }
        if (-not $guid -or $LASTEXITCODE -ne 0) {
            Write-Warning 'High Performance plan is unavailable on this firmware. Applying performance settings to the current plan.'
            Initialize-ShellRefresh
            $overlay = [guid]'ded574b5-45a0-4f42-8737-46345c09c238'
            $overlayResult = [FreshWindowsSetup.ShellSettings]::PowerSetActiveOverlayScheme([ref]$overlay)
            if ($overlayResult -ne 0) { Write-Warning "Best Performance overlay is unavailable (code $overlayResult)." }
        }
    }
    foreach ($mode in @('ac','dc')) {
        foreach ($item in @(
            @('monitor-timeout',5), @('standby-timeout',$sleepMinutes),
            @('hibernate-timeout',0), @('disk-timeout',0)
        )) {
            & powercfg.exe /change ($item[0] + '-' + $mode) $item[1]
            if ($LASTEXITCODE -ne 0) { throw "Cannot set $($item[0]) on $mode power." }
        }
        $valueSwitch = if ($mode -eq 'ac') { '/setacvalueindex' } else { '/setdcvalueindex' }
        & powercfg.exe $valueSwitch SCHEME_CURRENT SUB_BUTTONS LIDACTION $lidAction
        if ($LASTEXITCODE -ne 0) { throw "Cannot set lid action on $mode power." }
        foreach ($setting in @(
            @('SUB_PROCESSOR','PROCTHROTTLEMIN',100), @('SUB_PROCESSOR','PROCTHROTTLEMAX',100),
            @('SUB_PROCESSOR','PERFEPP',0), @('SUB_PCIEXPRESS','ASPM',0),
            @('2a737441-1930-4402-8d77-b2bebba308a3','48e6b7a6-50f5-4782-a5d4-53bb8f07e226',0),
            @('DE830923-A562-41AF-A086-E3A2C6BAD2DA','E69653CA-CF7F-4F05-AA73-CB833FA90AD4',0)
        )) {
            & powercfg.exe $valueSwitch SCHEME_CURRENT $setting[0] $setting[1] $setting[2]
            if ($LASTEXITCODE -ne 0) { Write-Warning "Hardware does not expose power setting $($setting[1]) on $mode." }
        }
    }
    & powercfg.exe /setactive SCHEME_CURRENT
    if ($LASTEXITCODE -ne 0) { throw 'Could not activate the configured power plan.' }
    & powercfg.exe /getactivescheme
    Write-Host "Profile $choice applied. Critical-battery protections are preserved."
}

function Open-BraveUBlockSetup {
    $brave = @(
        (Join-Path $env:ProgramFiles 'BraveSoftware\Brave-Browser\Application\brave.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'BraveSoftware\Brave-Browser\Application\brave.exe'),
        (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $brave) { throw 'Brave executable not found.' }
    $userData = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'
    $profiles = @(Get-ChildItem -LiteralPath $userData -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
    foreach ($profile in $profiles) {
        foreach ($id in @('jcokkipkhhgiakinbnnplhkdbjbgcgpe','cjpalhdlnbpafiamejdnhcphjbkeiagm')) {
            if (Test-Path -LiteralPath (Join-Path $profile.FullName "Extensions\$id")) {
                Write-Host 'uBlock Origin files are already present. Check its enabled state in Brave if needed.'
                return
            }
        }
    }
    Start-Process -FilePath $brave -ArgumentList 'brave://settings/extensions/v2'
    Write-Host 'In the Brave page just opened, switch uBlock Origin ON and accept its installation prompt.'
    Write-Host 'Brave hosts the full Manifest V2 extension; its old Chrome Web Store force-install link is no longer reliable.'
    Read-Host 'After enabling uBlock Origin, press Enter here to continue' | Out-Null
    $found = Get-ChildItem -LiteralPath $userData -Filter manifest.json -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\Extensions\\(jcokkipkhhgiakinbnnplhkdbjbgcgpe|cjpalhdlnbpafiamejdnhcphjbkeiagm)\\' } |
        Select-Object -First 1
    if (-not $found) { throw 'uBlock Origin installation was not detected. Enable it at brave://settings/extensions/v2.' }
}

function Invoke-DriverExclusive {
    param([scriptblock]$Action)
    $mutex = New-Object Threading.Mutex($false, 'Local\FreshWindowsSetupDriverInstall')
    $locked = $false
    try {
        Write-Host 'Waiting for any other GPU/driver installation to finish...'
        try { $locked = $mutex.WaitOne() }
        catch [Threading.AbandonedMutexException] { $locked = $true }
        & $Action
    } finally { if ($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}

function Get-DriverTool {
    param([ValidateSet('SDIO','SDI')][string]$Tool)
    $cache = Join-Path $env:ProgramData "FreshWindowsSetup\DriverTools\$Tool"
    if (-not (Test-Path -LiteralPath $cache)) { New-Item -ItemType Directory -Path $cache -Force | Out-Null }
    if ($Tool -eq 'SDIO') {
        $html = (Invoke-WebRequest -UseBasicParsing 'https://www.glenn.delahoy.com/snappy-driver-installer-origin/').Content
        $versions = @([regex]::Matches($html, '/downloads/sdio/SDIO_([0-9.]+)\.zip') |
            ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending -Unique)
        if (-not $versions.Count) { throw 'Cannot discover the official SDIO archive.' }
        $version = $versions[0].ToString()
        $archive = Join-Path $cache "SDIO_$version.zip"
        $hash = if ($version -eq '2.0.4.887') { '9D92CDD3BEBF04D48E495B30277AE61EF2A61A67E1D164A6A241C1BC3A8A3D0B' } else { '' }
        if ($hash -and (Test-Path -LiteralPath $archive) -and (Get-FileHash -LiteralPath $archive).Hash -ne $hash) {
            Remove-Item -LiteralPath $archive -Force
        }
        if (-not (Test-Path -LiteralPath $archive)) {
            Get-Download "https://www.glenn.delahoy.com/downloads/sdio/SDIO_$version.zip" $archive -Sha256 $hash
        }
        Expand-Archive -LiteralPath $archive -DestinationPath $cache -Force
        $exe = Get-ChildItem -LiteralPath $cache -Filter 'SDIO_x64_R*.exe' -Recurse -File |
            Sort-Object { [int]([regex]::Match($_.Name,'R(\d+)').Groups[1].Value) } -Descending |
            Select-Object -First 1
    } else {
        $html = (Invoke-WebRequest -UseBasicParsing 'https://sdi-tool.org/download/').Content
        $match = [regex]::Match($html, 'https://driveroff\.net/sdi/SDI_R(\d+)\.7z', 'IgnoreCase')
        if (-not $match.Success) { throw 'Cannot discover the original SDI archive from its official download page.' }
        $revision = $match.Groups[1].Value
        $archive = Join-Path $cache "SDI_R$revision.7z"
        $hash = if ($revision -eq '2601') { '94014426534E870A76F57D28B30E6D972F217CF384837AC110ED778A262439CE' } else { '' }
        if ($hash -and (Test-Path -LiteralPath $archive) -and (Get-FileHash -LiteralPath $archive).Hash -ne $hash) {
            Remove-Item -LiteralPath $archive -Force
        }
        if (-not (Test-Path -LiteralPath $archive)) {
            Get-Download $match.Value $archive -Sha256 $hash
        }
        & "$env:SystemRoot\System32\tar.exe" -xf $archive -C $cache
        if ($LASTEXITCODE -ne 0) { throw 'Original SDI archive extraction failed.' }
        $exe = Get-ChildItem -LiteralPath $cache -Filter 'SDI_x64_R*.exe' -Recurse -File |
            Sort-Object { [int]([regex]::Match($_.Name,'R(\d+)').Groups[1].Value) } -Descending |
            Select-Object -First 1
    }
    if (-not $exe) { throw "No $Tool x64 executable found after extraction." }
    return $exe.FullName
}

function Invoke-SdioScript {
    param([string]$Exe, [string]$Phase)
    $work = Split-Path $Exe -Parent
    $jobFile = Join-Path $work "fresh-setup-$Phase.txt"
    $commands = @('verbose 384','logging on','enableinstall on','activetorrent 1','init',
        'checkupdates','onerror goto :failed')
    if ($Phase -eq 'indexes') {
        $commands += @('get indexes','onerror goto :failed')
    } else {
        # Only matching missing/newer/better drivers are selected; no older/worse replacements.
        # The install command downloads the required driver packs automatically.
        $commands += @('select missing newer better','install','onerror goto :failed')
    }
    $commands += @('echo FRESH_SETUP_SDIO_SUCCESS','end',':failed','echo FRESH_SETUP_SDIO_FAILED','end')
    Set-Content -LiteralPath $jobFile -Value $commands -Encoding ASCII
    $log = Join-Path $runDir ("sdio-$Phase-" + (Get-Date -Format 'HHmmssfff') + '.log')
    Push-Location $work
    try {
        & $Exe "-script:$jobFile" 2>&1 | Tee-Object -FilePath $log | Out-Host
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    $output = Get-Content -LiteralPath $log -Raw
    if ($code -ne 0 -or $output -match 'FRESH_SETUP_SDIO_FAILED' -or $output -notmatch 'FRESH_SETUP_SDIO_SUCCESS') {
        throw "SDIO $Phase failed or crashed. Log: $log"
    }
}

function Invoke-DriverWorkflow {
    $tool = 'SDIO'
    $automatic = $true
    do {
        try {
            $exe = Get-DriverTool $tool
            if ($tool -eq 'SDIO' -and $automatic) {
                Write-Host 'Downloading all SDIO indexes first; driver packs are downloaded only for selected hardware.'
                Invoke-SdioScript $exe 'indexes'
                Invoke-DriverExclusive { Invoke-SdioScript $exe 'install' }
            } else {
                # GUI reopen is intentional: it lets the user check the result after a crash or install.
                Write-Host 'In the driver tool, download indexes only, then select matching missing/newer/better drivers and Install.'
                Write-Host 'Do not restart until the entire setup has finished. Close the driver tool when done.'
                Invoke-DriverExclusive {
                    $process = Start-Process -FilePath $exe -ArgumentList '-checkupdates' -WorkingDirectory (Split-Path $exe -Parent) -PassThru
                    $process.WaitForExit()
                    if ($process.ExitCode -ne 0) { Write-Warning "$tool closed with code $($process.ExitCode). You can reopen below." }
                }
            }
        } catch { Write-Warning "$tool : $($_.Exception.Message)" }
        Write-Host "`n$tool has finished or closed. Are all drivers installed correctly?"
        Write-Host "1) Reopen the same tool ($tool) to check or retry."
        Write-Host '2) Switch between SDIO and original SDI.'
        Write-Host '3) Finish: drivers are OK.'
        Write-Host '4) Finish: some drivers still need attention.'
        do { $choice = Read-Host 'Choose 1, 2, 3 or 4' } until ($choice -in @('1','2','3','4'))
        $automatic = $false
        if ($choice -eq '2') { $tool = if ($tool -eq 'SDIO') { 'SDI' } else { 'SDIO' } }
        if ($choice -eq '4') { throw 'User reports incomplete driver installation. Re-run the driver workflow when ready.' }
    } while ($choice -notin @('3','4'))
    $devices = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' |
        Where-Object { $_.ConfigManagerErrorCode -ne 22 })
    if ($devices.Count) {
        $devices | Select-Object Name,ConfigManagerErrorCode | Format-Table -AutoSize
        throw 'Device Manager still reports device errors. Some may need a restart or vendor-specific drivers.'
    }
    Write-Host 'Driver check accepted; no enabled devices currently report an error.'
}

function Remove-OneDrive {
    $oneDriveInstalled = $false
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        & winget.exe list --id Microsoft.OneDrive --exact --source winget --disable-interactivity --accept-source-agreements
        if ($LASTEXITCODE -eq 0) {
            $oneDriveInstalled = $true
            & winget.exe uninstall --id Microsoft.OneDrive --exact --silent --disable-interactivity --accept-source-agreements
            if ($LASTEXITCODE -ne 0) { throw "OneDrive uninstall returned $LASTEXITCODE." }
        }
    }
    if (-not $oneDriveInstalled) {
        $oneDrive = @((Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
            (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe')) |
            Where-Object { Test-Path -LiteralPath $_ }
        if ($oneDrive) {
            $setup = @("$env:SystemRoot\SysWOW64\OneDriveSetup.exe", "$env:SystemRoot\System32\OneDriveSetup.exe") |
                Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $setup) { throw 'OneDrive is present but its uninstaller cannot be found.' }
            Invoke-Installer $setup '/uninstall'
        }
    }
    # Retain OneDrive folders and synced documents. Only the application is uninstalled.
}

function Remove-Xbox {
    $xboxNames = @('Microsoft.GamingApp','Microsoft.XboxApp','Microsoft.Xbox.TCUI',
        'Microsoft.XboxGameOverlay','Microsoft.XboxGamingOverlay','Microsoft.XboxIdentityProvider',
        'Microsoft.XboxSpeechToTextOverlay','Microsoft.GamingServices')
    foreach ($name in $xboxNames) {
        Get-AppxPackage -AllUsers -Name $name | ForEach-Object {
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers
        }
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $name | ForEach-Object {
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName | Out-Null
        }
    }
    $remaining = @(foreach ($name in $xboxNames) { Get-AppxPackage -AllUsers -Name $name })
    if ($remaining.Count) { throw 'Some Xbox components remain installed; review the removal log.' }
}

function Disable-UnwantedStartup {
    Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0
    Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0
    Set-Dword 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'BackgroundModeEnabled' 0
    $target = '(?i)rustdesk|onedrive|(?:^|[^a-z])(?:brave|msedge)\.exe|BraveAutoLaunch|MicrosoftEdgeAutoLaunch|Xbox'
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')) {
        if (-not (Test-Path -LiteralPath $key)) { continue }
        $properties = (Get-ItemProperty -LiteralPath $key).PSObject.Properties |
            Where-Object { $_.Name -notlike 'PS*' }
        foreach ($entry in $properties) {
            if (($entry.Name + ' ' + [string]$entry.Value) -match $target) {
                Write-Host "Disabling startup entry: $($entry.Name)"
                Remove-ItemProperty -LiteralPath $key -Name $entry.Name
            }
        }
    }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($folder in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
        foreach ($link in @(Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -ErrorAction SilentlyContinue)) {
            $shortcut = $shell.CreateShortcut($link.FullName)
            if (($link.Name + ' ' + $shortcut.TargetPath) -match $target) {
                $backup = Join-Path $runDir ('disabled-startup-' + [guid]::NewGuid().ToString('N') + '-' + $link.Name)
                Move-Item -LiteralPath $link.FullName -Destination $backup
            }
        }
    }
    $rustService = Get-Service -Name RustDesk -ErrorAction SilentlyContinue
    if ($rustService) { Set-Service -Name $rustService.Name -StartupType Manual }
    # Do not disable updater tasks, antivirus, drivers, or unknown startup entries.
    Write-Host 'RustDesk remains installed; its service now starts manually. Browser auto-start/background mode is disabled.'
    Write-Host 'Defender, Lightshot, NetTime, Ditto and Intel/AMD/NVIDIA utilities are preserved.'
}

function Install-WingetApp {
    param([string]$Id)
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'WinGet is unavailable; see the WinGet step in the report.'
    }
    & winget.exe list --id $Id --exact --source winget --disable-interactivity --accept-source-agreements
    $verb = if ($LASTEXITCODE -eq 0) { 'upgrade' } else { 'install' }
    $arguments = @($verb, '--id', $Id, '--exact', '--source', 'winget', '--silent',
        '--disable-interactivity', '--accept-source-agreements', '--accept-package-agreements')
    if ($verb -eq 'upgrade') { $arguments += '--include-unknown' }
    & winget.exe @arguments
    $code = $LASTEXITCODE
    # WinGet returns 0x8A15002B when the installed package has no applicable upgrade.
    if ($code -notin @(0, -1978335189, 3010)) { throw "WinGet $Id returned $code." }
    & winget.exe list --id $Id --exact --source winget --disable-interactivity --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "WinGet could not verify an installed package for $Id." }
}

try {
    if ($Worker -eq 'Coordinator') {
    Invoke-Step 'Restore point and desktop registry backups' {
        $backupIndex = 0
        foreach ($key in @(
            'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer',
            'HKCU\Software\Microsoft\Windows\CurrentVersion\Search',
            'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
            'HKCU\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}',
            'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
        )) {
            $backupIndex++
            $file = Join-Path $runDir ("$backupIndex-" + (Split-Path $key -Leaf) + '.reg')
            & reg.exe export $key $file /y
            if ($LASTEXITCODE -ne 0) { Write-Warning "Could not export $key (may not exist yet)." }
        }
        Enable-ComputerRestore -Drive "$env:SystemDrive\"
        $restoreDescription = 'Before Fresh Windows Setup ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        $recent = Get-ComputerRestorePoint | Sort-Object SequenceNumber -Descending | Select-Object -First 1
        $canReuse = $recent -and ([Management.ManagementDateTimeConverter]::ToDateTime($recent.CreationTime) -gt (Get-Date).AddHours(-24))
        try { Checkpoint-Computer -Description $restoreDescription -RestorePointType MODIFY_SETTINGS }
        catch { if (-not $canReuse) { throw }; Write-Warning 'Reusing the existing restore point from the last 24 hours.' }
        $verified = Get-ComputerRestorePoint | Sort-Object SequenceNumber -Descending | Select-Object -First 1
        if (-not $verified -or ($verified.Description -ne $restoreDescription -and -not $canReuse)) {
            throw 'A new or recent restore point could not be verified. Setup will not start.'
        }
        Write-Host "Restore point verified: $($verified.Description) (sequence $($verified.SequenceNumber))"
    }

    if ($script:Results[$script:Results.Count - 1].Status -ne 'Completed') {
        throw 'Restore-point step failed. Resolve it and run the BAT again.'
    }
    Set-Content -LiteralPath (Join-Path $runDir 'restore-ready.txt') -Value 'Restore point verified'

    Invoke-Step 'WinGet availability' {
        if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
            # Microsoft's supported WinGet repair/bootstrap command.
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
            Install-Module Microsoft.WinGet.Client -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
            Import-Module Microsoft.WinGet.Client
            Repair-WinGetPackageManager -AllUsers
        }
        & winget.exe --version
        if ($LASTEXITCODE -ne 0) { throw 'WinGet did not start successfully.' }
        & winget.exe source update --disable-interactivity
        if ($LASTEXITCODE -ne 0) { throw 'WinGet source refresh failed.' }
    }

    # Workers inherit the elevated token and each get a visible, separate console.
    foreach ($kind in @('Apps','Office','Drivers')) {
        if ($kind -eq 'Office' -and $SkipOffice) { continue }
        if ($kind -eq 'Drivers' -and $SkipDrivers) { continue }
        if ($kind -eq 'Apps' -and $SkipApps -and $SkipGpu -and $SkipNetTime) { continue }
        Invoke-Step "Start $kind terminal" {
            $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Worker ' + $kind + ' -RunRoot "' + $runDir + '"'
            foreach ($flag in @('SkipApps','SkipGpu','SkipNetTime','SkipOffice','SkipDrivers','SkipFinalCommand')) {
                if ($script:SetupParameters.ContainsKey($flag) -and $script:SetupParameters[$flag]) { $arguments += " -$flag" }
            }
            $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arguments -PassThru
            $script:Workers += [pscustomobject]@{Kind=$kind; Process=$process}
        }
    }
    Write-Host 'App, Office and driver terminals are running while this terminal applies tweaks.'
    }

    if ($Worker -eq 'Coordinator') {
    if (-not $SkipDebloat) {
        Invoke-Step 'Raphire default tweaks and default bloatware removal' {
            # Resolve the latest stable upstream release, pin it for this run and log its hash.
            $release = Invoke-RestMethod 'https://api.github.com/repos/Raphire/Win11Debloat/releases/latest'
            $tag = [uri]::EscapeDataString($release.tag_name)
            $commit = Invoke-RestMethod "https://api.github.com/repos/Raphire/Win11Debloat/commits/$tag"
            $revision = $commit.sha
            if ($revision -notmatch '^[a-fA-F0-9]{40}$') { throw 'Invalid upstream revision.' }
            Write-Host "Raphire stable release: $($release.tag_name), revision $revision"
            $zip = Join-Path $runDir 'Win11Debloat.zip'
            Get-Download "https://github.com/Raphire/Win11Debloat/archive/$revision.zip" $zip
            Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $runDir 'Raphire')
            $debloater = Join-Path $runDir "Raphire\Win11Debloat-$revision\Win11Debloat.ps1"
            # The coordinator already verified a restore point before launching workers.
            # Avoid a second snapshot while concurrent installations are in progress.
            $defaultsPath = Join-Path (Split-Path $debloater -Parent) 'Config\DefaultSettings.json'
            $defaults = Get-Content -LiteralPath $defaultsPath -Raw | ConvertFrom-Json
            $defaults.Settings = @($defaults.Settings | Where-Object { $_.Name -ne 'CreateRestorePoint' })
            $defaults | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $defaultsPath -Encoding UTF8
            $debloatLog = Join-Path $runDir 'raphire.log'
            & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile `
                -ExecutionPolicy Bypass -File $debloater -CLI -Silent -RunDefaults -RemoveApps `
                -AppRemovalTarget AllUsers -SkipExplorerRestart -LogPath $debloatLog
            if ($LASTEXITCODE -ne 0) { throw "Raphire returned $LASTEXITCODE. See raphire.log." }
            # Upstream logs per-feature failures without necessarily returning a failure exit code.
            if (Test-Path $debloatLog) {
                if (Select-String -Path $debloatLog -Pattern '\[ERROR\]|failed|failure' -Quiet) {
                    throw 'Raphire logged errors. Review raphire.log for incomplete changes.'
                }
            }
        }
    }

    Invoke-Step 'Dark theme, classic right-click, clean taskbar and End task' {
        $advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        Set-Dword $personalize 'AppsUseLightTheme' 0
        Set-Dword $personalize 'SystemUsesLightTheme' 0
        Set-Dword $advanced 'ShowTaskViewButton' 0
        Set-Dword $advanced 'TaskbarDa' 0
        Set-Dword $advanced 'TaskbarMn' 0
        Set-Dword $advanced 'ShowCopilotButton' 0
        Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0
        Set-Dword "$advanced\TaskbarDeveloperSettings" 'TaskbarEndTask' 1
        $classic = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
        if (-not (Test-Path -LiteralPath $classic)) { New-Item -Path $classic -Force | Out-Null }
        Set-Item -Path $classic -Value ''
        Write-Host 'End task appears when right-clicking a running app on the taskbar (Windows label follows your language).'
        Write-Host 'Sign out or restart after setup to refresh the desktop.'
    }

    Invoke-Step 'File Explorer: This PC, hide Home, disable and clear recent history' {
        $explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
        Set-Dword "$explorer\Advanced" 'LaunchTo' 1
        Set-Dword $explorer 'ShowRecent' 0
        Set-Dword $explorer 'ShowFrequent' 0
        Set-Dword $explorer 'ShowCloudFilesInQuickAccess' 0
        Set-Dword "$explorer\Advanced" 'Start_TrackDocs' 0
        $policies = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
        Set-Dword $policies 'NoRecentDocsHistory' 1
        Set-Dword $policies 'ClearRecentDocsOnExit' 1
        $home = 'HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}'
        if (-not (Test-Path -LiteralPath $home)) { New-Item -Path $home -Force | Out-Null }
        Set-Item -Path $home -Value 'CLSID_MSGraphHomeFolder'
        Set-Dword $home 'System.IsPinnedToNameSpaceTree' 0
        # Windows Shell API clears recent/frequent usage data, not the original documents.
        if (-not ('FreshWindowsSetup.RecentHistory' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace FreshWindowsSetup {
    public static class RecentHistory {
        [DllImport("shell32.dll")]
        public static extern void SHAddToRecentDocs(uint flags, IntPtr item);
    }
}
'@
        }
        [FreshWindowsSetup.RecentHistory]::SHAddToRecentDocs(0, [IntPtr]::Zero)
        # Clear Explorer's typed path history as well. This only removes a registry history key.
        $typedPaths = "$explorer\TypedPaths"
        if (Test-Path $typedPaths) { Remove-Item -LiteralPath $typedPaths -Force }
        Write-Host 'Explorer opens to This PC. Home, recent files, frequent folders and cloud recommendations are hidden.'
        Write-Host 'Windows recent-item history cleared; sign out or restart to refresh Explorer.'
    }

    Invoke-Step 'Verify dark theme and Explorer launch settings' {
        $personalize = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        $advanced = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        if ($personalize.AppsUseLightTheme -ne 0 -or $personalize.SystemUsesLightTheme -ne 0 -or $advanced.LaunchTo -ne 1) {
            throw 'Dark mode or This PC launch settings did not stick.'
        }
        Initialize-ShellRefresh
        $messageResult = [UIntPtr]::Zero
        [void][FreshWindowsSetup.ShellSettings]::SendMessageTimeout([IntPtr]0xffff, 0x1a,
            [UIntPtr]::Zero, 'ImmersiveColorSet', 2, 2000, [ref]$messageResult)
        Write-Host 'Both dark-theme settings and Explorer LaunchTo=This PC verified.'
    }
    Invoke-Step 'Choose power profile' { Set-PowerProfile }
    Write-Host 'Tweaks finished. Waiting for the other terminals...'

    } # Coordinator tweaks

    if ($Worker -eq 'Apps') {
    if (-not $SkipApps) {
        foreach ($id in @(
            'Google.Chrome', 'Brave.Brave', 'Microsoft.Edge', 'VideoLAN.VLC',
            '7zip.7zip', 'Ditto.Ditto', 'ALCPU.CoreTemp',
            'Geeks3D.FurMark.2', 'Skillbrains.Lightshot', 'IObit.IObitUnlocker'
        )) { Invoke-Step "Install/update $id" { Install-WingetApp $id } }
        Invoke-Step 'Enable full uBlock Origin in Brave' { Open-BraveUBlockSetup }
        Invoke-Step 'Install/update RustDesk from official release' {
            $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/rustdesk/rustdesk/releases/latest'
            $asset = $release.assets | Where-Object { $_.name -match '^rustdesk-.*-x86_64\.msi$' } |
                Select-Object -First 1
            if (-not $asset -or $asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') {
                throw 'The official RustDesk release has no x64 MSI with a SHA256 digest.'
            }
            $checksum = $Matches[1]
            $installedRustDesk = Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'
            if (Test-Path -LiteralPath $installedRustDesk) {
                $versionText = (Get-Item -LiteralPath $installedRustDesk).VersionInfo.ProductVersion
                $installedMatch = [regex]::Match($versionText, '\d+\.\d+\.\d+')
                $latestMatch = [regex]::Match($release.tag_name, '\d+\.\d+\.\d+')
                if ($installedMatch.Success -and $latestMatch.Success -and
                    [version]$installedMatch.Value -ge [version]$latestMatch.Value) {
                    Write-Host 'RustDesk is already up to date; keeping the installed version and configuration.'
                    return
                }
            }
            if ($asset.browser_download_url -notlike 'https://github.com/rustdesk/rustdesk/releases/download/*') {
                throw 'Unexpected RustDesk asset URL.'
            }
            $msi = Join-Path $runDir 'RustDesk-x64.msi'
            Get-Download $asset.browser_download_url $msi -Sha256 $checksum
            $log = Join-Path $runDir 'rustdesk-msi.log'
            Invoke-Installer "$env:SystemRoot\System32\msiexec.exe" "/i `"$msi`" /qn /norestart /l*v `"$log`""
            if (-not (Test-Path (Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'))) {
                throw 'RustDesk executable not found after MSI installation.'
            }
        }
    }

    if (-not $SkipNetTime) {
        Invoke-Step 'NetTime stable release and automatic service' {
            $service = Get-Service -Name NetTime -ErrorAction SilentlyContinue
            if (-not $service) {
                $setup = Join-Path $runDir 'NetTimeSetup-314.exe'
                Get-Download 'https://www.timesynctool.com/NetTimeSetup-314.exe' $setup `
                    '5E3A5CD4E7CE99C8A5701CBE50344CD0516BC9984681DE56F15ABDE414D9DBDE' 'Mark Griffiths'
                Invoke-Installer $setup '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
            }
            $service = Get-Service -Name NetTime -ErrorAction SilentlyContinue
            if (-not $service) { throw 'NetTime service was not created by the installer.' }
            Set-Service -Name NetTime -StartupType Automatic
            Start-Service -Name NetTime
            $service = Get-Service -Name NetTime
            if ($service.Status -ne 'Running') { throw 'NetTime service is not running.' }
            Write-Host 'NetTime is running as an automatic service, using its default time servers.'
        }
    }

    if (-not $SkipGpu) {
        Invoke-Step 'Detect GPU and launch appropriate vendor setup' {
            # PCI vendor IDs also work before a proper GPU driver has been installed.
            $adapters = @(Get-CimInstance Win32_VideoController)
            $pnp = @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Display'")
            $ids = @($adapters.PNPDeviceID) + @($pnp.PNPDeviceID)
            $found = $false
            foreach ($vendor in @('NVIDIA','AMD')) {
                $pattern = if ($vendor -eq 'NVIDIA') { 'VEN_10DE' } else { 'VEN_1002' }
                if (-not ($ids -match $pattern)) { continue }
                $found = $true
                $appPath = if ($vendor -eq 'NVIDIA') {
                    Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVIDIA app\CEF\NVIDIA app.exe'
                } else { Join-Path $env:ProgramFiles 'AMD\CNext\CNext\RadeonSoftware.exe' }
                if (Test-Path -LiteralPath $appPath) {
                    Write-Host "$vendor app is already installed. Check its driver update page when needed."
                    continue
                }
                if ($vendor -eq 'NVIDIA') {
                    $page = 'https://www.nvidia.com/en-us/software/nvidia-app/'
                    $regex = 'https://(?:us|international)\.download\.nvidia\.com/nvapp/client/[^"''<>\s]+\.exe'
                    $publisher = 'NVIDIA Corporation'
                } else {
                    $page = 'https://www.amd.com/en/support/download/drivers.html'
                    $regex = 'https://drivers\.amd\.com/drivers/installer/[^"''<>\s]+minimalsetup[^"''<>\s]*\.exe'
                    $publisher = 'Advanced Micro Devices'
                }
                $html = (Invoke-WebRequest -UseBasicParsing $page).Content
                $match = [regex]::Match($html, $regex, 'IgnoreCase')
                if (-not $match.Success) { throw "Cannot discover $vendor installer. Visit $page" }
                $file = Join-Path $runDir "$vendor-Setup.exe"
                Get-Download $match.Value $file -Publisher $publisher -AllowGpuSignatureFailure
                Write-Host "Complete the $vendor installer. Do not reboot until this script finishes."
                Invoke-DriverExclusive {
                    Invoke-Installer $file
                    Read-Host "After $vendor setup and any driver installation finish, press Enter here" | Out-Null
                }
                if (-not (Test-Path -LiteralPath $appPath)) {
                    throw "$vendor app was not detected after setup. Check its installer window for errors."
                }
                Write-Host "$vendor app detected after installation."
            }
            if (-not $found) { Write-Host 'No AMD or NVIDIA display device detected; GPU setup skipped.' }
        }
    }

    } # Apps worker

    if ($Worker -eq 'Drivers' -and -not $SkipDrivers) {
        Invoke-Step 'SDIO drivers and retry/original-SDI menu' { Invoke-DriverWorkflow }
    }

    if ($Worker -eq 'Office' -and -not $SkipOffice) {
        Invoke-Step 'Office 2024 Pro Plus x64 pt-PT from original Microsoft C2R installer' {
            $configKey = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
            $existing = Get-ItemProperty $configKey -ErrorAction SilentlyContinue
            if ($existing -and $existing.ProductReleaseIds -notmatch 'ProPlus2024Retail') {
                throw 'A different Click-to-Run Office product is installed. Resolve that conflict before installing this edition.'
            }
            if ($existing -and $existing.Platform -eq 'x64' -and $existing.ClientCulture -eq 'pt-pt' -and
                $existing.InstallationPath -and
                (Test-Path -LiteralPath (Join-Path $existing.InstallationPath 'root\Office16\WINWORD.EXE'))) {
                $client = Join-Path $env:CommonProgramFiles 'Microsoft Shared\ClickToRun\OfficeC2RClient.exe'
                if (-not (Test-Path -LiteralPath $client)) { throw 'Installed Office has no Click-to-Run update client.' }
                Invoke-Installer $client '/update user displaylevel=true forceappshutdown=false updatepromptuser=false'
                Write-Host 'Existing Office kept. Update requested; follow the Office update window for completion.'
                return
            }
            $setup = Join-Path $runDir 'Office2024-pt-PT-C2R.exe'
            $url = 'https://c2rsetup.officeapps.live.com/c2r/download.aspx?ProductreleaseID=ProPlus2024Retail&platform=x64&language=pt-pt&version=O16GA'
            Get-Download $url $setup -Publisher 'Microsoft Corporation'
            Write-Host 'Complete the Microsoft Office installer if it opens a window.'
            Invoke-Installer $setup
            $deadline = (Get-Date).AddMinutes(60)
            do {
                $config = Get-ItemProperty $configKey -ErrorAction SilentlyContinue
                $word = if ($config -and $config.InstallationPath) {
                    Join-Path $config.InstallationPath 'root\Office16\WINWORD.EXE'
                } else { '' }
                $ready = $config -and $config.ProductReleaseIds -match 'ProPlus2024Retail' -and
                    $config.Platform -eq 'x64' -and $config.ClientCulture -eq 'pt-pt' -and
                    $word -and (Test-Path -LiteralPath $word)
                if (-not $ready) { Start-Sleep -Seconds 10 }
            } until ($ready -or (Get-Date) -gt $deadline)
            if (-not $ready) { throw 'Office x64 pt-PT installation could not be verified within 60 minutes. Check the Microsoft installer.' }
            Write-Host 'Office product, architecture, language and Word executable detected. Office activation is separate.'
        }
    }
    if ($Worker -eq 'Coordinator') {
        foreach ($job in $script:Workers) {
            $statusPath = Join-Path $runDir ('status-' + $job.Kind + '.json')
            while (-not (Test-Path -LiteralPath $statusPath)) {
                $job.Process.Refresh()
                if ($job.Process.HasExited) {
                    $script:Results.Add([pscustomobject]@{Step=$job.Kind;Status='Needs attention';Detail='Worker exited without a report. Check its terminal.'})
                    break
                }
                Start-Sleep -Seconds 2
            }
            if (Test-Path -LiteralPath $statusPath) {
                foreach ($result in @(Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json)) {
                    $script:Results.Add($result)
                }
            }
        }
        # Run these after apps/Office/driver workers, so installers cannot recreate the entries afterwards.
        Invoke-Step 'Uninstall OneDrive' { Remove-OneDrive }
        Invoke-Step 'Uninstall Xbox components' { Remove-Xbox }
        Invoke-Step 'Disable unwanted startup programs' { Disable-UnwantedStartup }
        Invoke-Step 'Refresh File Explorer and dark mode' {
            # Reapply after installers, which can modify desktop preferences.
            Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 0
            Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' 0
            Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1
            Initialize-ShellRefresh
            $messageResult = [UIntPtr]::Zero
            [void][FreshWindowsSetup.ShellSettings]::SendMessageTimeout([IntPtr]0xffff, 0x1a,
                [UIntPtr]::Zero, 'ImmersiveColorSet', 2, 2000, [ref]$messageResult)
            # Terminate only this user's Explorer shell in the current session.
            Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $sessionId | Stop-Process -Force
            Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList 'shell:MyComputerFolder'
        }
        if (-not $SkipFinalCommand) {
            # Keep remote execution in a child PowerShell: its exit cannot close the setup/report process.
            Invoke-Step 'Launch final requested command' {
                Write-Host 'Running the requested final command now. Complete its menu and close it to return to setup.'
                & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass `
                    -Command 'irm https://get.activated.win | iex'
                if ($LASTEXITCODE -ne 0) { throw "Final command process returned $LASTEXITCODE." }
                Write-Host 'The requested final command returned. This confirms launch/return, not activation status.'
            }
        }
    }
} catch {
    Write-Warning $_.Exception.Message
    $script:Results.Add([pscustomobject]@{Step="$Worker fatal error";Status='Needs attention';Detail=$_.Exception.Message})
} finally {
    $reportName = if ($Worker -eq 'Coordinator') { 'report.csv' } else { 'report-' + $Worker + '.csv' }
    $script:Results | Export-Csv -Path (Join-Path $runDir $reportName) -NoTypeInformation -Encoding UTF8
    $script:Results | Format-Table -AutoSize
    Write-Host "`nLogs, backups and report: $runDir"
    if ($Worker -eq 'Coordinator') {
        $issues = @($script:Results | Where-Object Status -eq 'Needs attention')
        if ($issues.Count) { Write-Warning "$($issues.Count) step(s) need attention. Review report.csv." }
        else { Write-Host 'All recorded setup steps finished.' -ForegroundColor Green }
        Write-Host 'Restart manually after all four terminals and vendor installers have finished.'
    }
    else {
        $statusPath = Join-Path $runDir ('status-' + $Worker + '.json')
        $temporary = $statusPath + '.tmp'
        ConvertTo-Json -InputObject @($script:Results.ToArray()) -Depth 5 | Set-Content -LiteralPath $temporary -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $statusPath
    }
    Stop-Transcript | Out-Null
    if ($Worker -eq 'Coordinator' -and $script:RunMutex) {
        $script:RunMutex.ReleaseMutex()
        $script:RunMutex.Dispose()
    }
}
Read-Host 'This terminal finished. Press Enter to close it' | Out-Null
if (@($script:Results | Where-Object Status -eq 'Needs attention').Count -gt 0) { exit 1 }
exit 0
