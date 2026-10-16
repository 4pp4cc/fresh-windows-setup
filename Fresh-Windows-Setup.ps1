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

Created/customized by GZ / 4pp4cc. Support: https://ko-fi.com/gzred
Project: https://github.com/4pp4cc/fresh-windows-setup
Credits: Raphire/Win11Debloat, Glenn Delahoy (SDIO), the original SDI project,
and the respective software vendors. These projects are independent.
WARNING: This script changes Windows settings, removes apps (including Xbox
and OneDrive), installs drivers/software and launches the requested remote
command. Review it first and keep a separate backup of important files.
A restore point is required but is not a full backup. Provided AS IS with no
guarantee or warranty. GPU signature checks may be bypassed for official
vendor downloads as requested. Performance settings increase battery use.
Installed uBlock extensions are left alone; setup no longer installs them.
SDIO/SDI downloads are retained through retries and deleted on driver terminal exit.
Debug .log files are retained under ProgramData\FreshWindowsSetup\Logs.
Structured last-run state is retained under ProgramData\FreshWindowsSetup\State.
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
    [switch]$CleanSetupFiles,
    [ValidateSet('All','Debloat','Software','Office','Drivers','Gpu')][string]$Part = 'All',
    [ValidateRange(0,3)][int]$DebloatLevel = 0,
    [ValidateSet('Coordinator','Apps','Office','Drivers','Manufacturer')][string]$Worker = 'Coordinator',
    [string]$RunRoot
)

$ErrorActionPreference = 'Stop'
$script:SetupParameters = $PSBoundParameters
if ($Worker -eq 'Coordinator' -and $Part -ne 'All') {
    $SkipDebloat = $Part -ne 'Debloat'
    $SkipApps = $Part -ne 'Software'
    $SkipNetTime = $Part -ne 'Software'
    $SkipOffice = $Part -ne 'Office'
    $SkipDrivers = $Part -ne 'Drivers'
    $SkipGpu = $Part -ne 'Gpu'
}
foreach ($flag in @('SkipDebloat','SkipApps','SkipNetTime','SkipOffice','SkipDrivers','SkipGpu','SkipFinalCommand')) {
    $script:SetupParameters[$flag] = [bool](Get-Variable -Name $flag -ValueOnly)
}
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
        $script:Results.Add([pscustomobject]@{Step=$Name; Status='Needs attention'; Detail=($_.Exception.Message + ' ' + $_.InvocationInfo.PositionMessage)})
    }
}

function Get-Download {
    param([string]$Url, [string]$Destination, [string]$Sha256, [string]$Publisher,
        [switch]$AllowGpuSignatureFailure, [hashtable]$Headers = @{})
    if (([uri]$Url).Scheme -ne 'https') { throw 'Only HTTPS downloads are accepted.' }
    $savedProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination -Headers $Headers
    } finally { $ProgressPreference = $savedProgress }
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

function Save-SetupLogs {
    param([string]$SourceRoot,[ValidateSet('Drivers','Setup')][string]$Label)
    $root = (Resolve-Path -LiteralPath $SourceRoot).ProviderPath.TrimEnd('\')
    $base = Join-Path $env:ProgramData 'FreshWindowsSetup'
    $logRoot = Join-Path $base ('Logs\' + (Split-Path $runDir -Leaf) + '\' + $Label)
    foreach ($folder in @($base,(Join-Path $base 'Logs'),(Split-Path $logRoot -Parent),$logRoot)) {
        if (Test-Path -LiteralPath $folder) {
            if ((Get-Item -LiteralPath $folder -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Log preservation refuses linked folders.' }
        } else { New-Item -ItemType Directory -Path $folder | Out-Null }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.log' -File -Recurse -Force)) {
        if (-not $file.FullName.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected log source path.' }
        $relative = $file.FullName.Substring($root.Length + 1)
        $destination = Join-Path $logRoot $relative
        $parent = Split-Path $destination -Parent
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }
    Write-Host "Debug logs retained: $logRoot"
}

function Save-SetupState {
    $base = Join-Path $env:ProgramData 'FreshWindowsSetup'
    $stateFolder = Join-Path $base 'State'
    if (Test-Path -LiteralPath $stateFolder) {
        if ((Get-Item -LiteralPath $stateFolder -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'State folder cannot be a link.' }
    } else { New-Item -ItemType Directory -Path $stateFolder | Out-Null }
    $remaining = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' |
        Where-Object { $_.ConfigManagerErrorCode -ne 22 } | Select-Object Name,ConfigManagerErrorCode,HardwareID)
    $path = Join-Path $stateFolder 'last-run.json'
    $history = @{}
    if ($Part -ne 'All' -and (Test-Path -LiteralPath $path)) {
        try {
            $previous = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            foreach ($entry in @($previous.RunHistory.PSObject.Properties)) { $history[$entry.Name] = $entry.Value }
        } catch { Write-Warning 'Previous run history could not be merged; this run is still recorded.' }
    }
    $now = (Get-Date).ToString('o')
    $history[$Part] = [pscustomobject]@{Time=$now;Results=@($script:Results.ToArray());UnresolvedDevices=$remaining}
    $state = [pscustomobject]@{LastRun=$now;Part=$Part;DebloatLevel=$DebloatLevel;ContextMenu=$script:ContextMenuChoice;RunHistory=$history;Results=@($script:Results.ToArray());UnresolvedDevices=$remaining}
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ($path + '.tmp') -Encoding UTF8
    Move-Item -LiteralPath ($path + '.tmp') -Destination $path -Force
    Write-Host "Last-run state retained: $path"
}

function Mark-WorkerInteractive {
    if ($Worker -eq 'Coordinator' -or $script:FinalReviewOpen) { return }
    $ready = Join-Path $runDir ('ready-' + $Worker + '.txt')
    Set-Content -LiteralPath $ready -Value 'Worker is ready for input; questions remain available immediately'
    $script:FinalReviewOpen = $true
}

function Read-Host {
    param([string]$Prompt,[switch]$AsSecureString)
    Mark-WorkerInteractive
    Microsoft.PowerShell.Utility\Read-Host @PSBoundParameters
}

function Get-GpuInstaller {
    param([string]$Vendor,[string]$Page,[string]$Pattern,[string]$Publisher)
    $file = Join-Path $runDir "$Vendor-Setup.exe"
    do {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Write-Host "$Vendor official server download: attempt $attempt of 3"
                $html = (Invoke-WebRequest -UseBasicParsing -Uri $Page).Content
                $match = [regex]::Match($html,$Pattern,'IgnoreCase')
                if (-not $match.Success) { throw 'No official vendor download link found on the current page.' }
                Get-Download $match.Value $file -Publisher $Publisher -AllowGpuSignatureFailure `
                    -Headers @{Referer=$Page; 'User-Agent'='Mozilla/5.0'}
                $stream = [IO.File]::OpenRead($file)
                try { $validExe = $stream.ReadByte() -eq 77 -and $stream.ReadByte() -eq 90 }
                finally { $stream.Dispose() }
                if (-not $validExe) { throw 'Vendor server returned a page/error instead of an EXE.' }
                return $file
            } catch {
                Write-Warning "$Vendor download failed: $($_.Exception.Message)"
                if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
                if ($attempt -lt 3) { Start-Sleep -Seconds 5 }
            }
        }
        Write-Host "`n1) Retry direct official-server download"
        Write-Host '2) Open vendor page in Edge and select a downloaded installer'
        Write-Host '3) Skip GPU installation (report needs attention)'
        do { $choice = Read-Host 'Choose 1, 2 or 3' } until ($choice -in @('1','2','3'))
        if ($choice -eq '3') { throw 'GPU installation skipped after download failures.' }
        if ($choice -eq '2') {
            Open-SetupLink $Page
            $localFile = (Read-Host 'Full path to the downloaded vendor EXE').Trim().Trim('"')
            if (-not (Test-Path -LiteralPath $localFile -PathType Leaf)) { Write-Warning 'File not found.'; continue }
            $signature = Get-AuthenticodeSignature -LiteralPath $localFile
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch $Publisher) {
                Write-Warning 'File has no valid matching vendor signature.'; continue
            }
            return $localFile
        }
    } while ($true)
}

function Get-EdgeExecutable {
    $paths = @((Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'))
    $edge = $paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $edge) { throw 'Microsoft Edge executable was not found.' }
    return $edge
}

function Open-SetupLink {
    param([string]$Url)
    if (([uri]$Url).Scheme -notin @('https','http')) { throw 'Expected a web URL.' }
    Start-Process -FilePath (Get-EdgeExecutable) -ArgumentList ('"' + $Url + '"')
}

function Set-EdgeDefaultPreference {
    $preferences = Join-Path $env:ProgramData 'FreshWindowsSetup\Preferences'
    New-Item -ItemType Directory -Path $preferences -Force | Out-Null
    $xmlPath = Join-Path $preferences 'EdgeDefaults.xml'
    $xml = '<?xml version="1.0" encoding="UTF-8"?><DefaultAssociations>' +
        '<Association ApplicationName="Microsoft Edge" ProgId="MSEdgeHTM" Identifier="http"/>' +
        '<Association ApplicationName="Microsoft Edge" ProgId="MSEdgeHTM" Identifier="https"/>' +
        '<Association ApplicationName="Microsoft Edge" ProgId="MSEdgeHTM" Identifier=".htm"/>' +
        '<Association ApplicationName="Microsoft Edge" ProgId="MSEdgeHTM" Identifier=".html"/></DefaultAssociations>'
    [IO.File]::WriteAllText($xmlPath,$xml,(New-Object Text.UTF8Encoding($false)))
    $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    if (-not (Test-Path -LiteralPath $policy)) { New-Item -Path $policy -Force | Out-Null }
    New-ItemProperty -Path $policy -Name 'DefaultAssociationsConfiguration' -Value $xmlPath -PropertyType String -Force | Out-Null
    & "$env:SystemRoot\System32\dism.exe" /Online ("/Import-DefaultAppAssociations:$xmlPath")
    if ($LASTEXITCODE -ne 0) { throw 'Could not import the Edge default associations.' }
    Write-Host 'Edge default associations configured for new profiles/policy-supported sign-in. Existing profiles may still require Settings > Default apps.'
    Write-Host 'Every web link opened by this setup uses Edge directly now, with no browser chooser.'
}

function Invoke-DriverRescan {
    & "$env:SystemRoot\System32\pnputil.exe" /scan-devices
    if ($LASTEXITCODE -ne 0) { Write-Warning "Device rescan returned $LASTEXITCODE." }
}

function Test-OfficialDriverUrl {
    param([string]$Url)
    try {
        $uri = [uri]$Url
        if ($uri.Scheme -ne 'https' -or $uri.UserInfo) { return $false }
        if ($uri.Host -in @('github.com','raw.githubusercontent.com') -and
            $uri.AbsolutePath -match '^/coolstar/driverinstallers(?:/|$)') { return $true }
        if ($uri.Host -in @('answers.microsoft.com','www.answers.microsoft.com','apps.microsoft.com')) { return $false }
        if ($uri.Host -eq 'www.microsoft.com' -and $uri.AbsolutePath -match 'microsoft-365|outlook|log-in') { return $false }
        foreach ($domain in @('dell.com','hp.com','lenovo.com','asus.com','acer.com','msi.com',
            'gigabyte.com','asrock.com','intel.com','amd.com','nvidia.com','realtek.com',
            'realtek.com.tw','qualcomm.com','mediatek.com','microsoft.com','surface.com','coolstar.org','coolstar.moe','ati.com')) {
            if ($uri.Host -eq $domain -or $uri.Host.EndsWith('.' + $domain)) { return $true }
        }
    } catch { }
    return $false
}

function Test-InfHardwareMatch {
    param([string]$Text,[string[]]$Ids)
    foreach ($line in ($Text -split '\r?\n')) {
        $record = ($line -split ';',2)[0]
        if ($record -notmatch '=') { continue }
        # Match a complete model hardware/compatible-ID field, never a substring/comment.
        $fields = (($record -split '=',2)[1] -split ',') | Select-Object -Skip 1
        foreach ($field in $fields) {
            if ($Ids -contains $field.Trim().Trim('"')) { return $true }
        }
    }
    return $false
}

function Get-DriverIdVariants {
    param([string[]]$Ids)
    $variants = @($Ids | Where-Object { $_ })
    $variants += @($Ids | ForEach-Object { $_ -replace '&REV_[0-9A-F]+','' })
    foreach ($id in $Ids) {
        if ($id -match '^(PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}|USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4})') { $variants += $Matches[1] }
    }
    return @($variants | Where-Object { $_ } | Select-Object -Unique)
}

function Get-DriverSearchQueries {
    param([string[]]$Ids,[string]$Context,[string]$DeviceName)
    $variants = @(Get-DriverIdVariants $Ids)
    if (-not $variants.Count) { return @() }
    $selected = @($Ids[0],($Ids[0] -replace '&REV_[0-9A-F]+',''))
    $base = @($variants | Where-Object { $_ -match '^(PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}|USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4})$' } | Select-Object -First 1)
    $selected += $base
    if ($Ids.Count -gt 1) { $selected += $Ids[1] -replace '&REV_[0-9A-F]+','' }
    $queries = @($selected | Select-Object -Unique | ForEach-Object { '"' + $_ + '" driver' })
    if ($Context) { $queries += '"' + (($selected | Select-Object -Last 1) -split '\\')[-1] + '" driver ' + $Context }
    if ($DeviceName -and $Context -and $DeviceName -notmatch 'Microsoft|Unknown|Generic|Desconhecido|Gen.rico') { $queries += '"' + $DeviceName + '" driver ' + $Context }
    return @($queries | Select-Object -Unique -First 6)
}

function Expand-DriverContainer {
    param([string]$Archive,[string]$Destination,[switch]$TrustedPayload)
    $seven = @((Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
        (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $seven) { throw '7-Zip is not installed yet. Retry after the Apps terminal installs it.' }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    if ((Get-Item -LiteralPath $Destination -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Extraction destination cannot be a link.' }
    $listing = @(& $seven l -slt -p- $Archive 2>&1)
    if ($LASTEXITCODE -ne 0) {
        if ($TrustedPayload -and [IO.Path]::GetExtension($Archive) -eq '.exe') {
            $bytes = [IO.File]::ReadAllBytes($Archive)
            $unicode = [Text.Encoding]::Unicode.GetString($bytes)
            $ascii = [Text.Encoding]::ASCII.GetString($bytes)
            if (($unicode.Contains('extract_all:') -or $ascii.Contains('extract_all:')) -and
                ($unicode.Contains('InstallShield') -or $ascii.Contains('InstallShield'))) {
                # Revenera documents this as extraction only. Used only inside a verified publisher package.
                Write-Host 'Extracting verified publisher payload with InstallShield /extract_all (no driver setup).'
                Invoke-Installer $Archive ('/extract_all:"' + $Destination + '"') 2
                return $true
            }
        }
        return $false
    }
    $entries = $false
    foreach ($line in $listing) {
        if ([string]$line -match '^----------') { $entries = $true; continue }
        if (-not $entries) { continue }
        if ([string]$line -match '^(Symbolic Link|Hard Link) =') { throw 'Linked archive entry rejected.' }
        if ([string]$line -match '^Path = (.+)$') {
            $relative = $Matches[1].TrimStart([char]92,[char]47)
            if ($relative.Contains(':')) { throw 'Absolute archive entry rejected.' }
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $relative))
            if (-not $target.StartsWith($Destination.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Archive traversal rejected.' }
        }
    }
    Invoke-Installer $seven ('x "' + $Archive + '" -o"' + $Destination + '" -y -p- -bd -bso0 -bsp0') 5
    return $true
}

function ConvertFrom-DriverCatalogXml {
    param([string]$Text)
    $settings = New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $inputText = New-Object IO.StringReader($Text.TrimStart([char]0xfeff))
    $reader = [Xml.XmlReader]::Create($inputText,$settings)
    try {
        $document = New-Object Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($reader)
        return ,$document
    } finally { $reader.Dispose(); $inputText.Dispose() }
}

function Get-OemDriverCatalog {
    param([ValidateSet('Dell','HP','Lenovo')][string]$Vendor,[string]$Cache)
    if (-not $script:OemCatalogs) { $script:OemCatalogs = @{} }
    if ($script:OemCatalogs.ContainsKey($Vendor)) { return ,$script:OemCatalogs[$Vendor] }
    $folder = Join-Path $Cache 'Catalogs'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    if ((Get-Item -LiteralPath $folder -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Catalog cache cannot be a link.' }
    $xmlPath = Join-Path $folder ($Vendor + '.xml')
    if ($Vendor -eq 'Lenovo') {
        Get-Download 'https://download.lenovo.com/cdrt/td/catalogv2.xml' $xmlPath
    } else {
        $url = if ($Vendor -eq 'Dell') { 'https://downloads.dell.com/catalog/DriverPackCatalog.cab' }
            else { 'https://ftp.hp.com/pub/caps-softpaq/cmit/HPClientDriverPackCatalog.cab' }
        $cab = Join-Path $folder ($Vendor + '.cab')
        Get-Download $url $cab
        & "$env:SystemRoot\System32\expand.exe" $cab $xmlPath | Out-Host
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $xmlPath)) { throw "$Vendor catalog extraction failed." }
    }
    $catalog = ConvertFrom-DriverCatalogXml ([IO.File]::ReadAllText($xmlPath))
    $script:OemCatalogs[$Vendor] = $catalog
    return ,$catalog
}

function Select-OemDriverPack {
    param([string]$Vendor,[xml]$Catalog,[string]$Model,[string[]]$SystemIds,[string]$Release)
    $candidates = @()
    $identity = @($SystemIds | Where-Object { $_ } | ForEach-Object { $_.Trim().ToUpperInvariant() })
    switch ($Vendor) {
        'Dell' {
            foreach ($pack in @($Catalog.DriverPackManifest.DriverPackage)) {
                if ($pack.type -ne 'win') { continue }
                $os = @($pack.SupportedOperatingSystems.OperatingSystem | Where-Object {
                    $_.osCode -eq 'Windows11' -and $_.osArch -eq 'x64' -and $_.osVendor -eq 'Microsoft' })
                if (-not $os.Count) { continue }
                $models = @($pack.SupportedSystems.Brand | ForEach-Object { $_.Model })
                $match = @($models | Where-Object { ($identity -contains ([string]$_.systemID).ToUpperInvariant()) -or $_.name -eq $Model })
                if (-not $match.Count) { continue }
                $sha = @($pack.Cryptography.Hash | Where-Object { $_.algorithm -eq 'SHA256' } | ForEach-Object { $_.InnerText }) | Select-Object -First 1
                $candidates += [pscustomobject]@{Name="Dell Windows 11 driver pack: $Model";Url=('https://downloads.dell.com/' + $pack.path);
                    Publisher='Dell';Sha256=$sha;Date=[string]$pack.dateTime;ExactRelease=$true;Size=[long]$pack.size;
                    ExtractKind='Dell';Note='Model-matched Windows 11 x64 driver pack. Driver INF installation only; no BIOS flashing.'}
            }
        }
        'HP' {
            $packs = @($Catalog.SelectNodes("//*[local-name()='SoftPaq']"))
            foreach ($mapping in @($Catalog.SelectNodes("//*[local-name()='ProductOSDriverPack']"))) {
                if ($mapping.Architecture -ne '64-bit' -or $mapping.OSName -notmatch '^Windows 11 ') { continue }
                $boardIds = @(([string]$mapping.SystemId -split ',') | ForEach-Object { $_.Trim().ToUpperInvariant() })
                if ($mapping.SystemName -ne $Model -and -not @($boardIds | Where-Object { $identity -contains $_ }).Count) { continue }
                foreach ($pack in @($packs | Where-Object { $_.Id -eq $mapping.SoftPaqId })) {
                    $candidates += [pscustomobject]@{Name=[string]$pack.Name;Url=[string]$pack.Url;Publisher='HP Inc\.|Hewlett-Packard';
                        Sha256=[string]$pack.SHA256;Date=[string]$pack.DateReleased;ExactRelease=([string]$mapping.OSName -match [regex]::Escape($Release));
                        Size=[long]$pack.Size;ExtractKind='HP';Note=('Model-matched driver pack: ' + $mapping.OSName + '. No Windows 10 fallback.')}
                }
            }
        }
        'Lenovo' {
            foreach ($entry in @($Catalog.ModelList.Model)) {
                if ($entry.arch -match 'ARM') { continue }
                $types = @($entry.Types.Type | ForEach-Object { ([string]$_).ToUpperInvariant() })
                if ($entry.name -ne $Model -and -not @($types | Where-Object { $identity -contains $_ }).Count) { continue }
                foreach ($pack in @($entry.SCCM | Where-Object { $_.os -eq 'win11' -and $_.InnerText -notmatch 'arm64|aarch64' })) {
                    $candidates += [pscustomobject]@{Name=('Lenovo Windows 11 driver pack: ' + $entry.name);Url=$pack.InnerText.Trim();
                        Publisher='Lenovo';Sha256=[string]$pack.crc;Date=[string]$pack.date;ExactRelease=($pack.version -eq $Release -or $pack.version -eq '*');
                        Size=0;ExtractKind='Lenovo';Note=('Model/type-matched Windows 11 driver pack, release ' + $pack.version + '. No BIOS package selected.')}
                }
            }
        }
    }
    return $candidates | Where-Object { $_.Sha256 -match '^[a-fA-F0-9]{64}$' -and (Test-OfficialDriverUrl $_.Url) } |
        Sort-Object @{Expression={$_.ExactRelease};Descending=$true},@{Expression={try {[datetime]$_.Date} catch {[datetime]::MinValue}};Descending=$true} |
        Select-Object -First 1
}

function Invoke-OemDriverCatalog {
    param([object]$Computer,[string]$Cache,[string[]]$Ids)
    $vendor = switch -Regex ($Computer.Manufacturer) {
        'Dell' { 'Dell'; break }; 'HP|Hewlett' { 'HP'; break }; 'Lenovo' { 'Lenovo'; break }
    }
    if (-not $vendor) { Write-Host 'No supported model catalog for this manufacturer. Continuing with publisher/hardware-ID fallback.'; return }
    $board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
    $product = Get-CimInstance Win32_ComputerSystemProduct | Select-Object -First 1
    $release = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
    $systemIds = @([string]$Computer.SystemSKUNumber,[string]$board.Product,[string]$product.Version,[string]$Computer.Model)
    if ($vendor -eq 'Lenovo' -and ([string]$Computer.Model).Length -ge 4) { $systemIds += ([string]$Computer.Model).Substring(0,4) }
    Write-Host "Official catalog: $vendor | $($Computer.Model) | Windows 11 x64 $release"
    $catalog = Get-OemDriverCatalog $vendor $Cache
    $candidate = Select-OemDriverPack $vendor $catalog $Computer.Model $systemIds $release
    if (-not $candidate) { Write-Warning "$vendor catalog has no matching Windows 11 x64 pack with SHA256. No older-OS pack was substituted."; return }
    if (-not $candidate.ExactRelease) { Write-Warning 'No exact Windows release pack is available; using the latest vendor-listed Windows 11 pack for this model.' }
    if ($candidate.Size) { Write-Host ('Selected model pack download: {0:N2} GB; retained for retries until driver terminal exit.' -f ($candidate.Size / 1GB)) }
    Invoke-DirectDriverPackages $Ids $Cache -Candidates @($candidate)
}

function Invoke-DirectDriverPackages {
    param([string[]]$Ids,[string]$Cache,[object[]]$Candidates)
    if (-not $Candidates) { return }
    foreach ($candidate in $Candidates) {
        try {
            if (-not (Test-OfficialDriverUrl $candidate.Url)) { throw 'Unsupported publisher source.' }
            Write-Host "Direct publisher candidate: $($candidate.Name)"
            Write-Warning $candidate.Note
            $hashProvider = [Security.Cryptography.SHA256]::Create()
            try { $prefix = ([BitConverter]::ToString($hashProvider.ComputeHash([Text.Encoding]::UTF8.GetBytes($candidate.Url + '|' + $candidate.Sha256)))).Replace('-','').Substring(0,16) }
            finally { $hashProvider.Dispose() }
            $name = $prefix + '-' + [IO.Path]::GetFileName(([uri]$candidate.Url).AbsolutePath)
            $archive = Join-Path $Cache $name
            $root = Join-Path $Cache ([IO.Path]::GetFileNameWithoutExtension($name))
            if ((Test-Path -LiteralPath $root) -and ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Driver package folder cannot be a link.' }
            $ready = Join-Path $root 'extract-ready.txt'
            $reuse = $false
            if (Test-Path -LiteralPath $archive) {
                try {
                    if ($candidate.Sha256 -and (Get-FileHash -LiteralPath $archive).Hash -ne $candidate.Sha256) { throw 'Checksum mismatch.' }
                    if ([IO.Path]::GetExtension($archive) -eq '.exe') {
                        $sig = Get-AuthenticodeSignature -LiteralPath $archive
                        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch $candidate.Publisher) { throw 'Publisher signature invalid.' }
                    }
                    $reuse = $true
                } catch {
                    Write-Warning 'Cached package is incomplete/invalid; downloading it again.'
                    Remove-Item -LiteralPath $archive -Force
                }
            }
            if (-not $reuse) {
                $publisher = if ([IO.Path]::GetExtension($archive) -eq '.exe') { $candidate.Publisher } else { '' }
                Get-Download $candidate.Url $archive -Publisher $publisher -Sha256 $candidate.Sha256
            } else {
                Write-Host 'Reusing previously downloaded publisher package.'
            }
            if (-not (Test-Path -LiteralPath $ready)) {
                $expanded = $false
                if ($candidate.Sha256 -and [IO.Path]::GetExtension($archive) -eq '.exe' -and $candidate.ExtractKind -in @('Dell','HP','Lenovo')) {
                    New-Item -ItemType Directory -Path $root -Force | Out-Null
                    if ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Driver pack extraction folder cannot be a link.' }
                    $arguments = switch ($candidate.ExtractKind) {
                        'Dell' { '/s /e="' + $root + '"' }
                        'HP' { '/s /e /f "' + $root + '"' }
                        'Lenovo' { '/VERYSILENT /NORESTART /DIR="' + $root + '" /EXTRACT="YES"' }
                    }
                    Write-Host 'Extracting the SHA256-verified OEM driver pack; its full setup is not being installed.'
                    Invoke-Installer $archive $arguments 20
                    $expanded = $true
                } else {
                    $expanded = Expand-DriverContainer $archive $root -TrustedPayload
                }
                if (-not $expanded) { throw 'Package format is not supported by the archive extractor.' }
                # Extract nested containers; verified publisher extraction-only modes are allowed.
                $seen = @{}
                $count = 0
                for ($depth=0; $depth -lt 5; $depth++) {
                    $nested = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
                        $_.Extension -in @('.cab','.msi','.exe') -and -not $seen.ContainsKey($_.FullName) -and $_.Name -notmatch '^(dev32|dev64|dpinst|win732)\.exe$' } | Select-Object -First 12)
                    if (-not $nested.Count) { break }
                    foreach ($item in $nested) {
                        if ($count -ge 24) { break }
                        $seen[$item.FullName] = $true
                        $count++
                        $destination = Join-Path $item.DirectoryName ($item.Name + '.contents')
                        [void](Expand-DriverContainer $item.FullName $destination -TrustedPayload)
                    }
                    if ($count -ge 24) { break }
                }
                if (-not @(Get-ChildItem -LiteralPath $root -Filter '*.inf' -Recurse -File).Count) { throw 'No extractable INF drivers found. This installer format needs a separate supported adapter; it was not executed.' }
                Set-Content -LiteralPath $ready -Value 'Extraction completed'
            }
            Install-MatchingInfDrivers $root $Ids
        } catch {
            if ($_.Exception.Message -like 'Driver installation deferred:*') { throw }
            Write-Warning "Direct package could not complete: $($_.Exception.Message)"
            if ($null -ne $script:Results) { $script:Results.Add([pscustomobject]@{Step=('Driver package: ' + $candidate.Name);Status='Needs attention';Detail=$_.Exception.Message}) }
        }
    }
}

function Install-MatchingInfDrivers {
    param([string]$Folder,[string[]]$Ids)
    if (@(Get-ChildItem -LiteralPath $Folder -Recurse -Force |
        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Candidate contains linked files.' }
    foreach ($inf in @(Get-ChildItem -LiteralPath $Folder -Filter '*.inf' -Recurse -File)) {
        $text = Get-Content -LiteralPath $inf.FullName -Raw
        if ($text -match '(?im)^\s*Class\s*=\s*"?Firmware"?\s*(?:;.*)?$') { continue }
        if (-not (Test-InfHardwareMatch $text $Ids)) { continue }
        $catalogs = @([regex]::Matches($text, '(?im)^\s*CatalogFile(?:\.[^=\s]+)?\s*=\s*([^;\r\n]+)') |
            ForEach-Object { $_.Groups[1].Value.Trim().Trim('"') })
        $valid = $false
        foreach ($name in $catalogs) {
            if ([IO.Path]::GetFileName($name) -ne $name) { continue }
            $catalog = Join-Path $inf.DirectoryName $name
            if ((Test-Path -LiteralPath $catalog) -and (Get-AuthenticodeSignature -LiteralPath $catalog).Status -eq 'Valid') { $valid = $true }
        }
        if (-not $valid) { Write-Warning "Matching INF has no verified catalog: $($inf.Name)"; continue }
        Write-Host "Matching signed driver candidate: $($inf.FullName)"
        Invoke-DriverExclusive {
            & "$env:SystemRoot\System32\pnputil.exe" /add-driver $inf.FullName /install | Out-Host
            if ($LASTEXITCODE -notin @(0,3010)) { throw "PnPUtil rejected candidate ($LASTEXITCODE)." }
            if ($LASTEXITCODE -eq 3010) { Write-Warning 'Driver requires a restart after setup.' }
        }
    }
}

function Invoke-VerifiedPublisherDrivers {
    param([string[]]$Ids,[string]$Cache)
    # Publisher adapter: inspect INF IDs across the repository, not a particular board.
    if (-not ($Ids -match '^ACPI\\(?:VEN_GOOG|GOOG)')) { return }
    $root = Join-Path $Cache 'CoolStar'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    if ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Publisher cache cannot be a link.' }
    if (-not $script:PublisherInfIndex) {
        Write-Host 'Reading CoolStar publisher INF index directly from GitHub; no search engine required.'
        $commit = Invoke-RestMethod 'https://api.github.com/repos/coolstar/driverinstallers/commits/master'
        if ($commit.sha -notmatch '^[a-fA-F0-9]{40}$') { throw 'Invalid publisher commit.' }
        $script:PublisherRevision = $commit.sha
        $tree = Invoke-RestMethod ('https://api.github.com/repos/coolstar/driverinstallers/git/trees/' + $commit.commit.tree.sha + '?recursive=1')
        if ($tree.truncated -or $tree.sha -notmatch '^[a-fA-F0-9]{40}$') { throw 'Incomplete/invalid publisher index.' }
        $script:PublisherTree = $tree
        $index = @()
        foreach ($entry in @($tree.tree | Where-Object { $_.type -eq 'blob' -and $_.path -match '\.inf$' -and $_.size -lt 200000 })) {
            $url = 'https://raw.githubusercontent.com/coolstar/driverinstallers/' + $script:PublisherRevision + '/' + $entry.path
            $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 30
            $index += [pscustomobject]@{Path=$entry.path;Text=$response.Content}
        }
        $script:PublisherInfIndex = $index
    }
    $matches = @($script:PublisherInfIndex | Where-Object { Test-InfHardwareMatch $_.Text $Ids })
    Write-Host "Publisher index: $($matches.Count) INF file(s) match current hardware IDs."
    foreach ($directory in @($matches | ForEach-Object { $_.Path.Substring(0,$_.Path.LastIndexOf('/')) } | Select-Object -Unique)) {
        $folder = Join-Path $root $directory.Replace('/','\')
        $ready = Join-Path $folder 'download-ready.txt'
        if (-not (Test-Path -LiteralPath $ready)) {
            foreach ($entry in @($script:PublisherTree.tree | Where-Object {
                $_.type -eq 'blob' -and $_.path.StartsWith($directory + '/') -and $_.path -match '\.(inf|cat|sys|dll|bin|dat)$' })) {
                $target = [IO.Path]::GetFullPath((Join-Path $root $entry.path.Replace('/','\')))
                if (-not $target.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe publisher path.' }
                $parent = Split-Path $target -Parent
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
                $url = 'https://raw.githubusercontent.com/coolstar/driverinstallers/' + $script:PublisherRevision + '/' + $entry.path
                Write-Host "Publisher package file: $($entry.path)"
                Get-Download $url $target
            }
            Set-Content -LiteralPath $ready -Value $script:PublisherRevision
        } else { Write-Host 'Reusing publisher package downloaded earlier in this run.' }
        Install-MatchingInfDrivers $folder $Ids
    }
}

function Get-DriverSearchPages {
    param([string]$Query,[string[]]$Ids)
    if (-not $script:DriverSearchCache) { $script:DriverSearchCache = @{} }
    if (-not $script:DriverSearchFailures) { $script:DriverSearchFailures = @{} }
    if ($script:DriverSearchCache.ContainsKey($Query)) { return $script:DriverSearchCache[$Query] }
    foreach ($provider in @('Brave API','Bing RSS','DuckDuckGo HTML')) {
        if ($provider -eq 'Brave API' -and -not $env:BRAVE_SEARCH_API_KEY) { continue }
        if ($script:DriverSearchFailures[$provider] -ge 2) { continue }
        try {
            $urls = @()
            switch ($provider) {
                'Brave API' {
                    Write-Host 'Searching through Brave Search API.'
                    $data = Invoke-RestMethod -Uri ('https://api.search.brave.com/res/v1/web/search?q=' + [uri]::EscapeDataString($Query) + '&count=20') `
                        -Headers @{'X-Subscription-Token'=$env:BRAVE_SEARCH_API_KEY;Accept='application/json'} -TimeoutSec 30
                    $urls = @($data.web.results | ForEach-Object { $_.url })
                }
                'Bing RSS' {
                    Write-Host 'Trying Bing RSS search.'
                    $response = Invoke-WebRequest -UseBasicParsing -Uri ('https://www.bing.com/search?q=' + [uri]::EscapeDataString($Query) + '&format=rss') -TimeoutSec 30
                    [xml]$rss = $response.Content
                    $urls = @($rss.rss.channel.item | ForEach-Object { [string]$_.link })
                }
                'DuckDuckGo HTML' {
                    Write-Host 'Trying DuckDuckGo search.'
                    $response = Invoke-WebRequest -UseBasicParsing -Uri ('https://html.duckduckgo.com/html/?q=' + [uri]::EscapeDataString($Query)) -TimeoutSec 30
                    if ($response.Content -match 'challenge-form|anomaly-modal') {
                        $script:DriverSearchFailures[$provider] = 2
                        throw 'CAPTCHA requested; source disabled for this run.'
                    }
                    $urls = @([regex]::Matches($response.Content, '(?i)uddg=([^&"<>]+)') |
                        ForEach-Object { [uri]::UnescapeDataString($_.Groups[1].Value) })
                }
            }
            $pages = @($urls | Select-Object -Unique -First 8 | Where-Object {
                if (-not (Test-OfficialDriverUrl $_)) { return $false }
                # Provider URLs alone are insufficient: require hardware-ID relevance in the page.
                try {
                    $pageResponse = Invoke-WebRequest -UseBasicParsing -Uri $_ -TimeoutSec 20
                    $content = [Net.WebUtility]::HtmlDecode($pageResponse.Content)
                    $relevant = $false
                    foreach ($id in $Ids) {
                        $suffix = ($id -split '\\')[-1]
                        if ($content.IndexOf($id,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                            $content.IndexOf($suffix,[StringComparison]::OrdinalIgnoreCase) -ge 0) { $relevant = $true }
                    }
                    $relevant -and (Test-OfficialDriverUrl $pageResponse.BaseResponse.ResponseUri.AbsoluteUri)
                } catch { $false }
            } | Select-Object -Unique -First 4)
            if ($pages.Count) { $script:DriverSearchCache[$Query] = $pages; return $pages }
            Write-Host "$provider returned no supported manufacturer links; trying the next source."
            # No result for an exact ID is not a provider outage: broader ID queries must still run.
        } catch {
            # Do not print API response bodies or headers, which may include credentials.
            Write-Warning "$provider unavailable or blocked. Trying the next source."
            $script:DriverSearchFailures[$provider] = 1 + [int]$script:DriverSearchFailures[$provider]
        }
    }
    $script:DriverSearchCache[$Query] = @()
    if (-not $script:SearchUnavailableReported) {
        Write-Warning 'Search sources returned no relevant results or were blocked. Blocked/failing sources will not be repeatedly queried in this run. Direct publisher matching remains available. BRAVE_SEARCH_API_KEY enables authenticated search.'
        $script:SearchUnavailableReported = $true
    }
    return @()
}

function Invoke-AutomaticWebDrivers {
    Show-DriverProblems
    Invoke-DriverRescan
    Write-Host 'Automatic official model catalogs first, then publisher/hardware-ID fallback. No SDI and no Windows Update API.'
    Write-Host 'Supported automatic packages: publisher INF packages, ZIP/CAB archives and verified extractable EXE containers. Only matching signed INF drivers are installed.'
    $computer = Get-CimInstance Win32_ComputerSystem
    $context = "$($computer.Manufacturer) $($computer.Model)"
    $cache = Join-Path $env:ProgramData 'FreshWindowsSetup\DriverTools\HardwareWeb'
    foreach ($part in @((Join-Path $env:ProgramData 'FreshWindowsSetup'),
        (Join-Path $env:ProgramData 'FreshWindowsSetup\DriverTools'),$cache)) {
        if (-not (Test-Path -LiteralPath $part)) { New-Item -ItemType Directory -Path $part | Out-Null }
        if ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Hardware search cache cannot be a link.' }
    }
    if (-not $script:WebDriverSeen) { $script:WebDriverSeen = @{} }
    $extractor = @((Join-Path $env:ProgramFiles '7-Zip\7z.exe'),(Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe')) |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $extractor) { Invoke-Step '7-Zip dependency for automatic driver extraction' { Install-WingetApp '7zip.7zip' } }
    $devices = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' |
        Where-Object { $_.ConfigManagerErrorCode -ne 22 })
    $inventory = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 22 })
    $allIds = @($inventory | ForEach-Object { @($_.HardwareID) + @($_.CompatibleID) } | Where-Object { $_ } | Select-Object -Unique)
    Write-Host 'Manufacturer catalog work runs independently in the Manufacturer terminal. This window continues hardware-ID/publisher matching.'
    try { Invoke-VerifiedPublisherDrivers $allIds $cache } catch { Write-Warning "Publisher matching failed: $($_.Exception.Message)" }
    Invoke-DriverRescan
    $devices = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' |
        Where-Object { $_.ConfigManagerErrorCode -ne 22 })
    foreach ($device in $devices) {
        $ids = @(@($device.HardwareID) + @($device.CompatibleID) | Where-Object { $_ } | Select-Object -Unique)
        $searchIds = @(Get-DriverIdVariants $ids)
        if (-not $ids.Count) { Write-Warning "No hardware ID: $($device.Name)"; continue }
        Write-Host "`nSearching: $($device.Name) | $($ids[0]) | error $($device.ConfigManagerErrorCode)"
        foreach ($query in @(Get-DriverSearchQueries $ids $context $device.Name)) {
            try {
                Write-Host "Web query: $query"
                $pages = @(Get-DriverSearchPages $query $searchIds)
                if (-not $pages.Count) { Write-Warning "No relevant supported publisher results for $($ids[0])." }
                foreach ($page in $pages) {
                    Write-Host "Manufacturer result: $page"
                    $urls = @()
                    if (([uri]$page).AbsolutePath -match '\.(zip|cab|exe)$') { $urls = @($page) }
                    else {
                        $response = Invoke-WebRequest -UseBasicParsing -Uri $page -TimeoutSec 30
                        $finalPage = $response.BaseResponse.ResponseUri.AbsoluteUri
                        if (-not (Test-OfficialDriverUrl $finalPage)) { throw 'Manufacturer page redirected outside supported sources.' }
                        $urls = @([regex]::Matches($response.Content, '(?i)href\s*=\s*["'']([^"'']+)["'']') |
                            ForEach-Object {
                                try { ([uri]::new([uri]$finalPage,[Net.WebUtility]::HtmlDecode($_.Groups[1].Value))).AbsoluteUri } catch { }
                            } | Where-Object { (Test-OfficialDriverUrl $_) -and ([uri]$_).AbsolutePath -match '\.(zip|cab|exe)$' } |
                            Select-Object -Unique -First 3)
                    }
                    foreach ($url in $urls) {
                        try {
                            if (([uri]$url).AbsolutePath -match '\.exe$') {
                                Invoke-DirectDriverPackages $ids $cache -Candidates @([pscustomobject]@{
                                    Name='Signed publisher driver container';Url=$url;Publisher='.';
                                    Note='Extracting a signed publisher container. Its complete driver installer will not be run.'})
                                continue
                            }
                            $sha = [Security.Cryptography.SHA256]::Create()
                            try { $key = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($url)))).Replace('-','').ToLowerInvariant() }
                            finally { $sha.Dispose() }
                            $extension = [IO.Path]::GetExtension(([uri]$url).AbsolutePath)
                            $archive = Join-Path $cache ($key + $extension)
                            $folder = Join-Path $cache $key
                            if (-not $script:WebDriverSeen.ContainsKey($url)) {
                                Write-Host "Downloading candidate: $url"
                                $download = Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive -PassThru -TimeoutSec 120
                                if (-not (Test-OfficialDriverUrl $download.BaseResponse.ResponseUri.AbsoluteUri)) { throw 'Package redirected outside supported manufacturer sources.' }
                                Write-Host "Candidate SHA256: $((Get-FileHash -LiteralPath $archive).Hash)"
                                New-Item -ItemType Directory -Path $folder -Force | Out-Null
                                if ($extension -eq '.zip') {
                                    Add-Type -AssemblyName System.IO.Compression.FileSystem
                                    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
                                    try {
                                        foreach ($entry in $zip.Entries) {
                                            $target = [IO.Path]::GetFullPath((Join-Path $folder $entry.FullName))
                                            if (-not $target.StartsWith($folder + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe archive entry.' }
                                        }
                                    } finally { $zip.Dispose() }
                                    Expand-Archive -LiteralPath $archive -DestinationPath $folder -Force
                                } else {
                                    & "$env:SystemRoot\System32\expand.exe" '-F:*' $archive $folder | Out-Host
                                    if ($LASTEXITCODE -ne 0) { throw 'CAB extraction failed.' }
                                }
                                $script:WebDriverSeen[$url] = $folder
                            } else { $folder = $script:WebDriverSeen[$url]; Write-Host 'Reusing candidate already downloaded in this run.' }
                            Install-MatchingInfDrivers $folder $ids
                        } catch {
                            if ($_.Exception.Message -like 'Driver installation deferred:*') { throw }
                            Write-Warning "Candidate failed: $($_.Exception.Message)"
                        }
                    }
                }
            } catch {
                if ($_.Exception.Message -like 'Driver installation deferred:*') { throw }
                Write-Warning "Internet search failed for $($ids[0]) : $($_.Exception.Message)"
            }
        }
    }
    Invoke-DriverRescan
    Show-DriverProblems
    Write-Host 'Internet search finished. Search results/package staging do not prove a device was fixed; the device list above is the current result.'
}

function Show-DriverProblems {
    $devices = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' |
        Where-Object { $_.ConfigManagerErrorCode -ne 22 })
    Write-Host "`nMissing/problem drivers (28 = missing; 10 = cannot start; 43 = device reported a problem):"
    if (-not $devices.Count) { Write-Host 'No enabled devices currently report a driver/device error.'; return }
    $devices | Select-Object Name,@{Name='Error';Expression={$_.ConfigManagerErrorCode}},
        @{Name='HardwareID';Expression={@($_.HardwareID)[0]}} | Format-Table -Wrap -AutoSize | Out-Host
}

function Select-DebloatLevel {
    Write-Host "`nDebloat level (first debloat question):"
    Write-Host '1) NORMAL - recommended: default app cleanup, privacy/AI/ads, keep everyday Windows tools and security'
    Write-Host '2) HIGH - minimal resources: more optional apps, reduced effects and background apps; keep security/update/store services'
    Write-Host '3) RADICAL - almost all catalogued optional apps plus service/security restrictions, for very slow PCs'
    Write-Warning 'Radical reduces Defender real-time protection, Windows Update, Store access and indexing after installations finish. It can break features. Normal/High do not undo a previous Radical run.'
    do { $selected = Microsoft.PowerShell.Utility\Read-Host 'Choose 1, 2 or 3' } until ($selected -in @('1','2','3'))
    return [int]$selected
}

function Get-DebloatProfile {
    param([ValidateRange(1,3)][int]$Level)
    $rap = @('DisableTelemetry','DisableSuggestions','DisableEdgeAds','DisableLockscreenTips','DisableBing',
        'DisableStoreSearchSuggestions','DisableCopilot','DisableRecall','DisableClickToDo','DisableAISvcAutoStart',
        'DisableWidgets','HideChat','ShowKnownFileExt','DisableDragTray','Hide3dObjects','DisableDVR',
        'DisableGameBarIntegration','DisableStartPhoneLink','DisableStartRecommended','DisableDeliveryOptimization',
        'PreventUpdateAutoReboot','DisableUpdateASAP','EnableDarkMode','ExplorerToThisPC','EnableEndTask','HideSearchTb','HideTaskview')
    $ctt = @('WPFTweaksActivity','WPFTweaksConsumerFeatures','WPFTweaksDeliveryOptimization','WPFTweaksDisableExplorerAutoDiscovery')
    if ($Level -ge 2) {
        $rap += @('DisableTransparency','DisableAnimations','DisableEdgeAI','DisablePaintAI',
            'DisableNotepadAI','DisableBraveBloat','DisableSettings365Ads','DisableSettingsHome','DisableDesktopSpotlight',
            'HideDesktopSpotlightIcon','HideHome','HideGallery','HideTabsInAltTab')
        $ctt += @('WPFTweaksDisplay','WPFTweaksDisableBGapps','WPFTweaksEdgeDebloat','WPFTweaksBraveDebloat')
    }
    if ($Level -eq 3) {
        $rap += @('DisableNotifications','DisableLocationServices','DisableFindMyDevice','DisableDeviceAutoAppDownload','ClearStart')
        $ctt += @('WPFTweaksServices','WPFTweaksReservedStorage','WPFTweaksStorage')
    }
    [pscustomobject]@{Level=$Level;Name=@('Normal','High','Radical')[$Level-1];Raphire=@($rap|Select-Object -Unique);Titus=@($ctt|Select-Object -Unique)}
}

function Get-DebloatAppSelection {
    param([object[]]$Apps,[int]$Level)
    $core = '^(Microsoft\.(Edge|WindowsStore|WindowsTerminal|DesktopAppInstaller)|XPFFTQ037JWMHS)$'
    $everyday = @('Microsoft.GetHelp','Microsoft.WindowsCalculator','Microsoft.WindowsNotepad','Microsoft.Paint',
        'Microsoft.Windows.Photos','Microsoft.WindowsCamera','Microsoft.ScreenSketch')
    foreach ($app in $Apps) {
        foreach ($id in @($app.AppId)) {
            if ($id -match $core) { continue }
            if ($id -match 'HPPowerManager|LenovoVantage|LenovoCompanion') { continue }
            $remove = [bool]$app.SelectedByDefault
            if ($Level -ge 2 -and $app.Recommendation -eq 'optional' -and $id -notin $everyday) { $remove = $true }
            if ($Level -eq 3) { $remove = $true }
            if ($remove) { $id }
        }
    }
}

function Invoke-TitusProfile {
    param([object]$Profile)
    # Reviewed release; a newer upstream release is not silently granted additional actions.
    $file = Join-Path $runDir 'winutil-26.10.07.ps1'
    Get-Download 'https://github.com/ChrisTitusTech/winutil/releases/download/26.10.07/winutil.ps1' $file `
        -Sha256 'eeae69922fbe6354ea4e2a37f705eaa17bdaf45cc7889618a313178a513b13ee'
    $config = Join-Path $runDir 'titus-profile.json'
    ConvertTo-Json -InputObject @($Profile.Titus) | Set-Content -LiteralPath $config -Encoding UTF8
    $log = Join-Path $runDir 'titus.log'
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $file -Config $config *> $log
    if ($LASTEXITCODE -ne 0) { throw "Chris Titus profile returned $LASTEXITCODE. See titus.log." }
}

function Select-ContextMenuStyle {
    Write-Host "`nRight-click menu:"
    Write-Host '1) Windows 11 new menu'
    Write-Host '2) Classic full menu (Windows 10 style)'
    do { $choice = Read-Host 'Choose 1 or 2' } until ($choice -in @('1','2'))
    $classic = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
    if ($choice -eq '2') {
        if (-not (Test-Path -LiteralPath $classic)) { New-Item -Path $classic -Force | Out-Null }
        Set-Item -LiteralPath $classic -Value ''
    } elseif (Test-Path -LiteralPath $classic) { Remove-Item -LiteralPath $classic -Recurse -Force }
    $script:ContextMenuChoice = [int]$choice
    Write-Host 'Menu preference saved. Sign out/restart to refresh Explorer fully.'
}



function Set-RadicalPreset {
    $stateFolder = Join-Path $env:ProgramData 'FreshWindowsSetup\State'
    if (-not (Test-Path -LiteralPath $stateFolder)) { New-Item -ItemType Directory -Path $stateFolder -Force | Out-Null }
    if ((Get-Item -LiteralPath $stateFolder -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Radical backup folder cannot be a link.' }
    $backupPath = Join-Path $stateFolder 'radical-before.json'
    if (-not (Test-Path -LiteralPath $backupPath)) {
        $services = @(Get-CimInstance Win32_Service | Where-Object Name -in @('wuauserv','UsoSvc','WSearch') |
            Select-Object Name,StartMode,State)
        $defender = Get-MpPreference -ErrorAction SilentlyContinue
        $store = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' -ErrorAction SilentlyContinue
        $updates = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
        [pscustomobject]@{Saved=(Get-Date).ToString('o');Services=$services;
            DefenderDisableRealtimeMonitoring=$defender.DisableRealtimeMonitoring;
            StoreRemoveWindowsStore=$store.RemoveWindowsStore;StoreAutoDownload=$store.AutoDownload;
            UpdatesNoAutoUpdate=$updates.NoAutoUpdate} | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $backupPath -Encoding UTF8
    }
    Write-Host "Original radical settings retained: $backupPath"
    Invoke-Step 'Radical: disable Defender real-time protection' {
        Set-MpPreference -DisableRealtimeMonitoring $true
        if ((Get-MpComputerStatus).RealTimeProtectionEnabled) { throw 'Windows/Tamper Protection kept Defender active. No protection bypass was attempted.' }
        Write-Warning 'Real-time protection disabled. Windows may automatically re-enable it.'
    }
    Invoke-Step 'Radical: disable automatic Windows Update' {
        Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 1
        foreach ($name in @('wuauserv','UsoSvc')) {
            if (Get-Service -Name $name -ErrorAction SilentlyContinue) {
                Set-Service -Name $name -StartupType Disabled
                Stop-Service -Name $name -Force
                $current = Get-CimInstance Win32_Service -Filter "Name='$name'"
                if ($current.StartMode -ne 'Disabled' -or $current.State -ne 'Stopped') { throw "$name could not be disabled/stopped." }
            }
        }
    }
    Invoke-Step 'Radical: restrict Microsoft Store and automatic Store updates' {
        Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' 'RemoveWindowsStore' 1
        Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' 'AutoDownload' 2
        Write-Warning 'Store restriction policies depend on Windows edition; installed Store apps and App Installer are retained.'
    }
    Invoke-Step 'Radical: disable Windows Search indexing' {
        Set-Service -Name WSearch -StartupType Disabled
        Stop-Service -Name WSearch -Force
        $current = Get-CimInstance Win32_Service -Filter "Name='WSearch'"
        if ($current.StartMode -ne 'Disabled' -or $current.State -ne 'Stopped') { throw 'Search indexing could not be disabled/stopped.' }
    }
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


function Invoke-DriverExclusive {
    param([scriptblock]$Action, [ValidateRange(0,300)][int]$WaitSeconds = 60)
    $mutex = New-Object Threading.Mutex($false, 'Local\FreshWindowsSetupDriverInstall')
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) {
            Write-Host "Another driver installer is running. Waiting automatically for up to $WaitSeconds seconds; no input is needed."
            try { $locked = $mutex.WaitOne($WaitSeconds * 1000) }
            catch [Threading.AbandonedMutexException] { $locked = $true }
        }
        if (-not $locked) {
            throw [TimeoutException]::new('Driver installation deferred: another driver installer is still running. Continuing other setup work. After the setup windows close, use launcher option 6 for AMD/NVIDIA, 5 for drivers, or 7 to retry failed parts.')
        }
        Write-Host 'Driver installation lock acquired; starting this operation.'
        & $Action
    } finally { if ($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}

function Get-DriverTool {
    param([ValidateSet('SDIO','SDI')][string]$Tool)
    if (-not $script:DriverToolExecutables) { $script:DriverToolExecutables = @{} }
    if ($script:DriverToolExecutables.ContainsKey($Tool) -and
        (Test-Path -LiteralPath $script:DriverToolExecutables[$Tool])) {
        Write-Host "Reusing downloaded $Tool and its existing indexes/driver packs."
        return $script:DriverToolExecutables[$Tool]
    }
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
    $script:DriverToolExecutables[$Tool] = $exe.FullName
    return $exe.FullName
}

function Invoke-SdioScript {
    param([string]$Exe, [string]$Phase)
    $work = Split-Path $Exe -Parent
    $jobFile = Join-Path $work "fresh-setup-$Phase.txt"
    $driverDirectory = Join-Path $work 'drivers'
    $indexDirectory = Join-Path $work 'indexes'
    $extractDirectory = Join-Path $work 'extracted'
    foreach ($directory in @($driverDirectory,$indexDirectory,$extractDirectory,
        (Join-Path $work 'logs'), (Join-Path $work 'update\SDIO_Update\drivers'))) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    # Relative directories are resolved from the explicit tool working directory below.
    # Avoid quote parsing differences between SDIO script-engine releases.
    $commands = @('drpdir drivers', 'indexdir indexes',
        'extractdir extracted', 'verbose 384','logging on','enableinstall on','init',
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
    if ($code -ne 0 -or $output -match 'FRESH_SETUP_SDIO_FAILED|Move error:|ERROR with (MoveFileEx|CopyFileEx)|extraction failed' -or $output -notmatch 'FRESH_SETUP_SDIO_SUCCESS') {
        throw "SDIO $Phase failed or crashed. Log: $log"
    }
}

function Remove-DriverToolFiles {
    $setupRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'FreshWindowsSetup'))
    $cacheRoot = [IO.Path]::GetFullPath((Join-Path $setupRoot 'DriverTools'))
    if (-not (Test-Path -LiteralPath $cacheRoot)) { return }
    $resolved = (Resolve-Path -LiteralPath $cacheRoot).ProviderPath
    if (-not [string]::Equals($resolved, $cacheRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not $resolved.StartsWith($setupRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Driver cleanup target is outside the expected setup cache.'
    }
    # Never follow a junction/symlink outside this setup-owned cache.
    foreach ($path in @($env:ProgramData, $setupRoot, $cacheRoot)) {
        if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Driver cleanup refuses linked folders: $path"
        }
    }
    $pending = New-Object 'Collections.Generic.Stack[string]'
    $pending.Push($cacheRoot)
    while ($pending.Count) {
        foreach ($item in @(Get-ChildItem -LiteralPath $pending.Pop() -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Driver cleanup refuses a linked item: $($item.FullName)"
            }
            if (-not $item.FullName.StartsWith($cacheRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Unexpected driver cleanup child path.'
            }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
        }
    }
    $running = @(Get-CimInstance Win32_Process | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith($cacheRoot + '\', [StringComparison]::OrdinalIgnoreCase)
    })
    if ($running.Count) { throw 'SDIO/SDI is still open. Close it before deleting its cache.' }
    Save-SetupLogs -SourceRoot $resolved -Label 'Drivers'
    Remove-Item -LiteralPath $resolved -Recurse -Force
    if (Test-Path -LiteralPath $cacheRoot) { throw 'SDIO/SDI cache remains; review the cleanup error.' }
    Write-Host 'Removed SDIO/SDI executables, archives, indexes and downloaded driver packs. Installed drivers are retained.'
}


function Invoke-DriverWorkflow {
    Write-Host "`nDriver method:"
    Write-Host '1) SDIO automatic terminal'
    Write-Host '2) SDIO graphical interface'
    Write-Host '3) Automatic official driver catalogs + hardware-ID fallback WITHOUT SDI'
    Write-Host '4) Original SDI graphical interface'
    if (-not $script:FinalReviewOpen) {
        $method = '3'
        Write-Host 'Automatic phase: using official catalogs/hardware matching (option 3). SDIO/SDI choices are available during final review.'
    } else {
        do { $method = Read-Host 'Choose 1, 2, 3 or 4' } until ($method -in @('1','2','3','4'))
    }
    $tool = switch ($method) { '1' { 'SDIO' }; '2' { 'SDIO' }; '3' { 'Internet hardware-ID search' }; '4' { 'SDI' } }
    $automatic = $method -eq '1'
    do {
        try {
            if ($tool -eq 'Internet hardware-ID search') { Invoke-AutomaticWebDrivers } else {
            $exe = Get-DriverTool $tool
            if ($tool -eq 'SDIO' -and $automatic) {
                if (-not $script:SdioIndexesReady) {
                    Write-Host 'Downloading SDIO indexes first; only selected hardware driver packs are downloaded.'
                    Invoke-SdioScript $exe 'indexes'
                    $script:SdioIndexesReady = $true
                } else { Write-Host 'Reusing indexes already downloaded in this run.' }
                Invoke-DriverExclusive { Invoke-SdioScript $exe 'install' }
            } else {
                # GUI reopen is intentional: it lets the user check the result after a crash or install.
                Write-Host 'Existing indexes and packs are retained. Download indexes only if absent/outdated.'
                Write-Host 'In the driver tool, select matching missing/newer/better drivers and Install.'
                Write-Host 'Do not restart until the entire setup has finished. Close the driver tool when done.'
                Invoke-DriverExclusive {
                    $process = Start-Process -FilePath $exe -ArgumentList '-checkupdates' -WorkingDirectory (Split-Path $exe -Parent) -PassThru
                    $process.WaitForExit()
                    if ($process.ExitCode -ne 0) { Write-Warning "$tool closed with code $($process.ExitCode). You can reopen below." }
                }
            }
            }
        } catch { Write-Warning "$tool : $($_.Exception.Message)" }
        Invoke-DriverRescan
        Show-DriverProblems
        Write-Host 'An installer success message does not confirm Bluetooth/Wi-Fi/audio actually works. Test the device before choosing Finish.'
        Write-Host "`n$tool has finished or closed. Are all drivers installed correctly?"
        Write-Host "1) Reopen the same tool ($tool) to check or retry."
        Write-Host '2) Switch between SDIO and original SDI.'
        Write-Host '3) Automatic official driver catalogs + hardware-ID fallback WITHOUT SDI.'
        Write-Host '4) Finish: drivers are OK.'
        Write-Host '5) Finish: some drivers still need attention.'
        Write-Host '6) Switch SDIO between automatic terminal and graphical interface'
        Write-Host '7) Installed but device does not work: choose an alternative driver (GUI, existing packs retained)'
        do { $choice = Read-Host 'Choose 1, 2, 3, 4, 5, 6 or 7' } until ($choice -in @('1','2','3','4','5','6','7'))
        if ($choice -eq '2') { $tool = if ($tool -eq 'SDIO') { 'SDI' } else { 'SDIO' }; $automatic = $false }
        if ($choice -eq '6') { $tool = 'SDIO'; $automatic = -not $automatic }
        if ($choice -eq '3') { $tool = 'Internet hardware-ID search' }
        if ($choice -eq '7') {
            if ($tool -eq 'Internet hardware-ID search') { $tool = 'SDIO' }
            $automatic = $false
            Write-Host 'Expand the affected device using its double arrows and try the next matching candidate, then test the device.'
            Write-Host 'Repeating terminal auto-install would select the preferred candidate again; this opens alternatives instead.'
        }
        if ($choice -eq '5') { throw 'User reports incomplete driver installation. Re-run the driver workflow when ready.' }
    } while ($choice -notin @('4','5'))
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

function Get-ChromeExecutable {
    @((Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')) |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

function Install-ChromeVerified {
    $wingetOk = $false
    try { Install-WingetApp 'Google.Chrome'; $wingetOk = $true }
    catch { Write-Warning "Chrome WinGet install/update failed: $($_.Exception.Message). Trying Google's MSI." }
    $chrome = Get-ChromeExecutable
    if (-not $wingetOk -or -not $chrome) {
        $msi = Join-Path $runDir 'GoogleChromeStandaloneEnterprise64.msi'
        Get-Download 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' $msi -Publisher 'Google'
        $log = Join-Path $runDir 'chrome-msi.log'
        Invoke-Installer "$env:SystemRoot\System32\msiexec.exe" ('/i "' + $msi + '" /qn /norestart ALLUSERS=1 /L*v "' + $log + '"')
        $chrome = Get-ChromeExecutable
    }
    if (-not $chrome) { throw 'Chrome executable is missing after installation. See chrome-msi.log and the Apps report.' }
    $version = (Get-Item -LiteralPath $chrome).VersionInfo.ProductVersion
    if (-not $version) { throw 'Chrome executable has no readable version information.' }
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    if ($desktop) {
        if (-not (Test-Path -LiteralPath $desktop)) { New-Item -ItemType Directory -Path $desktop -Force | Out-Null }
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Google Chrome.lnk'))
        $shortcut.TargetPath = $chrome
        $shortcut.WorkingDirectory = Split-Path $chrome -Parent
        $shortcut.IconLocation = $chrome + ',0'
        $shortcut.Save()
    }
    Write-Host "Chrome verified: $version | $chrome | desktop shortcut created."
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
    Write-Host 'Fresh Windows Setup - GZ / 4pp4cc' -ForegroundColor Cyan
    Write-Host 'Project: https://github.com/4pp4cc/fresh-windows-setup'
    Write-Host 'Support / Ko-Fi: https://ko-fi.com/gzred'
    Write-Host 'Credits: Raphire/Win11Debloat, Glenn Delahoy/SDIO, original SDI and software vendors.'
    $previousState = Join-Path $env:ProgramData 'FreshWindowsSetup\State\last-run.json'
    if (Test-Path -LiteralPath $previousState) {
        try {
            $previous = Get-Content -LiteralPath $previousState -Raw | ConvertFrom-Json
            $previousFailures = @($previous.Results | Where-Object Status -eq 'Needs attention')
            Write-Host "Previous run: $($previous.LastRun); $($previousFailures.Count) step(s) previously needed attention."
            Write-Host 'Installed versions and current hardware are checked again before updating.'
        } catch { Write-Warning 'Previous-run state is unreadable; continuing with fresh checks.' }
    }
    Write-Warning 'AS IS, without guarantee or warranty. Keep a backup: a restore point is not a full backup.'
    Write-Warning 'Setup removes apps, changes settings, installs drivers and runs the requested final remote command.'
    Write-Warning 'Official GPU signature-check failures may be bypassed. Performance settings increase battery use.'
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
    Set-Content -LiteralPath (Join-Path $runDir 'coordinator-process.txt') -Value $PID
    if (-not $SkipDebloat) {
        if ($DebloatLevel -eq 0) { $DebloatLevel = Select-DebloatLevel }
        $script:DebloatProfile = Get-DebloatProfile $DebloatLevel
        $script:RadicalRequested = $DebloatLevel -eq 3
        Write-Host ('Selected debloat profile: ' + $script:DebloatProfile.Name)
    }

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

    Invoke-Step 'Edge default-browser preference and direct setup links' { Set-EdgeDefaultPreference }
    # Workers inherit the elevated token and each get a visible, separate console.
    foreach ($kind in @('Apps','Office','Drivers','Manufacturer')) {
        if ($kind -eq 'Office' -and $SkipOffice) { continue }
        if ($kind -in @('Drivers','Manufacturer') -and $SkipDrivers) { continue }
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

    if ($Worker -eq 'Coordinator' -and -not $SkipDebloat) {
    if (-not $SkipDebloat) {
        Invoke-Step 'Raphire selected debloat profile and app removal' {
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
            $basePath = Split-Path $debloater -Parent
            $available = (Get-Content (Join-Path $basePath 'Config\Features.json') -Raw | ConvertFrom-Json).Features.FeatureId
            $appCatalog = (Get-Content (Join-Path $basePath 'Config\Apps.json') -Raw | ConvertFrom-Json).Apps
            $cttAppFile = Join-Path $runDir 'titus-appx-catalog.json'
            Get-Download 'https://raw.githubusercontent.com/ChrisTitusTech/winutil/26.10.07/config/appx.json' $cttAppFile
            $cttApps = Get-Content -LiteralPath $cttAppFile -Raw | ConvertFrom-Json
            $appCatalog = @($appCatalog) + @($cttApps.PSObject.Properties | ForEach-Object {
                [pscustomobject]@{AppId=$_.Value.PackageId;FriendlyName=$_.Value.Content;Recommendation='optional';SelectedByDefault=$false}
            })
            $selectedApps = @(Get-DebloatAppSelection $appCatalog $DebloatLevel | Select-Object -Unique)
            $settings = @($script:DebloatProfile.Raphire | Where-Object { $_ -in $available } |
                ForEach-Object { [pscustomobject]@{Name=$_;Value=$true} })
            $profilePath = Join-Path $runDir 'raphire-profile.json'
            [pscustomobject]@{Version='1.0';Apps=$selectedApps;Tweaks=$settings} |
                ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $profilePath -Encoding UTF8
            Write-Host "Profile $DebloatLevel`: $($settings.Count) Raphire settings, $($selectedApps.Count) catalogued apps selected."
            $debloatLog = Join-Path $runDir 'raphire.log'
            & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile `
                -ExecutionPolicy Bypass -File $debloater -CLI -Silent -Config $profilePath `
                -AppRemovalTarget AllUsers -SkipExplorerRestart -LogPath $debloatLog
            if ($LASTEXITCODE -ne 0) { throw "Raphire returned $LASTEXITCODE. See raphire.log." }
            # Upstream logs per-feature failures without necessarily returning a failure exit code.
            if (Test-Path $debloatLog) {
                if (Select-String -Path $debloatLog -Pattern '\[ERROR\]|failed|failure' -Quiet) {
                    throw 'Raphire logged errors. Review raphire.log for incomplete changes.'
                }
            }
        }
        Invoke-Step 'Chris Titus reviewed profile selections' { Invoke-TitusProfile $script:DebloatProfile }
    }

    Invoke-Step 'Dark theme, clean taskbar and End task' {
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
        $explorerHomeKey = 'HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}'
        if (-not (Test-Path -LiteralPath $explorerHomeKey)) { New-Item -Path $explorerHomeKey -Force | Out-Null }
        Set-Item -Path $explorerHomeKey -Value 'CLSID_MSGraphHomeFolder'
        Set-Dword $explorerHomeKey 'System.IsPinnedToNameSpaceTree' 0
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
    Write-Host 'Automatic tweaks finished. Waiting for automatic installations before cleanup and final questions...'

    } # Coordinator tweaks

    if ($Worker -eq 'Apps') {
    if (-not $SkipApps) {
        Invoke-Step 'Install/update Google Chrome and verify executable' { Install-ChromeVerified }
        foreach ($id in @(
            'Brave.Brave', 'Microsoft.Edge', 'VideoLAN.VLC',
            '7zip.7zip', 'Ditto.Ditto', 'ALCPU.CoreTemp',
            'Geeks3D.FurMark.2', 'Skillbrains.Lightshot', 'IObit.IObitUnlocker'
        )) { Invoke-Step "Install/update $id" { Install-WingetApp $id } }
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
            $service = Get-Service -Name NetTimeSvc,NetTime -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $service) {
                $setup = Join-Path $runDir 'NetTimeSetup-314.exe'
                Get-Download 'https://www.timesynctool.com/NetTimeSetup-314.exe' $setup `
                    '5E3A5CD4E7CE99C8A5701CBE50344CD0516BC9984681DE56F15ABDE414D9DBDE' 'Mark Griffiths'
                Invoke-Installer $setup '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
            }
            $service = Get-Service -Name NetTimeSvc,NetTime -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $service) { throw 'NetTime service was not created by the installer.' }
            Set-Service -Name $service.Name -StartupType Automatic
            Start-Service -InputObject $service
            $service = Get-Service -Name $service.Name
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
                $file = Get-GpuInstaller $vendor $page $regex $publisher
                $silentArguments = if ($vendor -eq 'NVIDIA') { '-s' } else { '-INSTALL' }
                Write-Host "Installing $vendor app silently. Do not reboot until setup finishes."
                $silentFailed = $false
                try {
                Invoke-DriverExclusive {
                    Invoke-Installer $file $silentArguments
                }
                Write-Host 'Installer process finished. Checking for the vendor app for up to 2 minutes; the driver lock is released.'
                $deadline = (Get-Date).AddMinutes(2)
                while (-not (Test-Path -LiteralPath $appPath) -and (Get-Date) -lt $deadline) {
                    Start-Sleep -Seconds 5
                }
                } catch { if ($_.Exception -is [TimeoutException]) { throw }; $silentFailed = $true; Write-Warning "Silent installer failed: $($_.Exception.Message)" }
                if ($silentFailed -or -not (Test-Path -LiteralPath $appPath)) {
                    Write-Host 'Silent installation did not produce the vendor app.'
                    Write-Host '1) Retry silent install'
                    Write-Host '2) Run installer with its visible interface'
                    Write-Host '3) Skip and report needs attention'
                    do { $retry = Read-Host 'Choose 1, 2 or 3' } until ($retry -in @('1','2','3'))
                    if ($retry -eq '3') { throw "$vendor app not detected after silent setup." }
                    Invoke-DriverExclusive {
                        if ($retry -eq '1') { Invoke-Installer $file $silentArguments }
                        else { Invoke-Installer $file }
                    }
                    if (-not (Test-Path -LiteralPath $appPath)) { throw "$vendor app still not detected. Review vendor installation errors." }
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
    if ($Worker -eq 'Manufacturer' -and -not $SkipDrivers) {
        Invoke-Step 'Manufacturer official driver catalog scan/download/install' {
            $computer = Get-CimInstance Win32_ComputerSystem
            $inventory = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 22 })
            $ids = @($inventory | ForEach-Object { @($_.HardwareID) + @($_.CompatibleID) } | Where-Object { $_ } | Select-Object -Unique)
            $cache = Join-Path $env:ProgramData 'FreshWindowsSetup\DriverTools\HardwareWeb'
            foreach ($folder in @((Join-Path $env:ProgramData 'FreshWindowsSetup'),(Join-Path $env:ProgramData 'FreshWindowsSetup\DriverTools'),$cache)) {
                if (Test-Path -LiteralPath $folder) {
                    if ((Get-Item -LiteralPath $folder -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Manufacturer cache cannot be a link.' }
                } else { New-Item -ItemType Directory -Path $folder | Out-Null }
            }
            Invoke-OemDriverCatalog $computer $cache $ids
            Invoke-DriverRescan
            Show-DriverProblems
        }
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
        if (-not $SkipFinalCommand) {
            Read-Host 'Close the Office installer/update window, then press Enter to run the requested activation command' | Out-Null
            Invoke-Step 'Requested command after Office setup closes' {
                Write-Host 'Opening the requested command in a separate elevated PowerShell window. Complete its menu and close that window to continue.'
                $activationScript = Join-Path $runDir 'Requested-Activation.ps1'
                @'
$ErrorActionPreference = 'Stop'
$activationLog = Join-Path $PSScriptRoot 'activation.log'
try {
    irm https://get.activated.win | iex
    'Requested command returned; activation status was not verified.' | Add-Content -LiteralPath $activationLog
    Read-Host 'Requested command returned. Press Enter to close this window' | Out-Null
    exit 0
} catch {
    $_ | Out-String | Add-Content -LiteralPath $activationLog
    Write-Warning ('Requested command failed or was blocked: ' + $_.Exception.Message)
    Write-Host 'Review Windows Security > Protection history. This setup does not hide the command or bypass Defender.'
    Write-Host ('Details retained in: ' + $activationLog)
    Read-Host 'Press Enter to close this window and return to Office setup' | Out-Null
    exit 1
}
'@ | Set-Content -LiteralPath $activationScript -Encoding UTF8
                $commandProcess = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
                    -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $activationScript + '"') -PassThru
                $commandProcess.WaitForExit()
                $commandProcess.Refresh()
                if ($commandProcess.ExitCode -ne 0) { throw "Requested command window returned $($commandProcess.ExitCode). Review its displayed error." }
                Write-Host 'Requested command window closed. This records process completion, not successful activation.'
            }
        }
    }
    if ($Worker -eq 'Coordinator') {
        foreach ($job in $script:Workers) {
            $statusPath = Join-Path $runDir ('status-' + $job.Kind + '.json')
            $readyPath = Join-Path $runDir ('ready-' + $job.Kind + '.txt')
            while (-not (Test-Path -LiteralPath $statusPath) -and -not (Test-Path -LiteralPath $readyPath)) {
                $job.Process.Refresh()
                if ($job.Process.HasExited) {
                    $script:Results.Add([pscustomobject]@{Step=$job.Kind;Status='Needs attention';Detail='Worker exited without a report. Check its terminal.'})
                    break
                }
                Start-Sleep -Seconds 2
            }
        }
        # Run these after apps/Office/driver workers, so installers cannot recreate the entries afterwards.
        if (-not $SkipDebloat) {
            Invoke-Step 'Uninstall OneDrive' { Remove-OneDrive }
            Invoke-Step 'Uninstall Xbox components' { Remove-Xbox }
        }
        if (-not $SkipApps -or -not $SkipDebloat) { Invoke-Step 'Disable unwanted startup programs' { Disable-UnwantedStartup } }
        if (-not $SkipApps) {
            Invoke-Step 'Final automatic Chrome presence check' {
                if (-not (Get-ChromeExecutable)) { Install-ChromeVerified }
                else { Write-Host ('Chrome present: ' + (Get-ChromeExecutable)) }
            }
        }
        if (-not $SkipDebloat) { Invoke-Step 'Refresh File Explorer and dark mode' {
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
        } }
        Write-Host 'Automatic installations, removals and baseline tweaks are complete. Final coordinator choices follow; worker retry menus remain independently available.'
        Set-Content -LiteralPath (Join-Path $runDir 'final-review.txt') -Value 'Automatic cleanup complete'
        if (-not $SkipDebloat) {
            Invoke-Step 'Final right-click menu preference' { Select-ContextMenuStyle }
            Invoke-Step 'Final power profile choice' { Set-PowerProfile }
        }
        foreach ($job in $script:Workers) {
            $statusPath = Join-Path $runDir ('status-' + $job.Kind + '.json')
            while (-not (Test-Path -LiteralPath $statusPath)) {
                $job.Process.Refresh()
                if ($job.Process.HasExited) { break }
                Start-Sleep -Seconds 1
            }
            if (Test-Path -LiteralPath $statusPath) {
                foreach ($result in @(Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json)) { $script:Results.Add($result) }
            } else { $script:Results.Add([pscustomobject]@{Step=$job.Kind;Status='Needs attention';Detail='Worker exited without a final report.'}) }
        }
        if ($script:RadicalRequested) { Invoke-Step 'Apply selected radical preset after all installation/retry work' { Set-RadicalPreset } }
        Write-Host 'Tweaks finished.'
    }
} catch {
    Write-Warning $_.Exception.Message
    $script:Results.Add([pscustomobject]@{Step="$Worker fatal error";Status='Needs attention';Detail=$_.Exception.Message})
} finally {
    if ($Worker -eq 'Coordinator' -and -not (Test-Path -LiteralPath (Join-Path $runDir 'final-review.txt'))) {
        Set-Content -LiteralPath (Join-Path $runDir 'final-review.txt') -Value 'Coordinator ended; review outstanding work'
    }
    $reportName = if ($Worker -eq 'Coordinator') { 'report.csv' } else { 'report-' + $Worker + '.csv' }
    $script:Results | Export-Csv -Path (Join-Path $runDir $reportName) -NoTypeInformation -Encoding UTF8
    $script:Results | Format-Table -AutoSize
    Write-Host "`nLogs, backups and report: $runDir"
    Write-Host "After exit, debug .log files remain under $env:ProgramData\FreshWindowsSetup\Logs."
    if ($Worker -eq 'Coordinator') {
        Write-Host 'Created by GZ / 4pp4cc - Support / Ko-Fi: https://ko-fi.com/gzred'
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
}
Read-Host 'This terminal finished. Press Enter to close it' | Out-Null
if ($Worker -eq 'Coordinator') {
    foreach ($job in $script:Workers) {
        $job.Process.Refresh()
        if (-not $job.Process.HasExited) {
            Write-Host "Waiting for the $($job.Kind) terminal to close. Review it and press Enter there."
            $job.Process.WaitForExit()
        }
        $job.Process.Refresh()
        if ($job.Process.ExitCode -ne 0) {
            Write-Warning "$($job.Kind) terminal exited with code $($job.Process.ExitCode)."
            $script:Results.Add([pscustomobject]@{Step="$($job.Kind) terminal exit";Status='Needs attention';Detail="Exit code $($job.Process.ExitCode); this includes cleanup failures."})
        }
    }
}
if ($Worker -eq 'Coordinator') {
    if (-not $SkipDrivers) { Invoke-Step 'Delete driver-tool downloads after all worker terminals exit' { Remove-DriverToolFiles } }
    try { Save-SetupState } catch { Write-Warning "Could not save last-run state: $($_.Exception.Message)" }
}
if ($Worker -eq 'Coordinator' -and $CleanSetupFiles) {
    try {
        $expectedParent = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'FreshWindowsSetup'))
        $target = (Resolve-Path -LiteralPath $runDir).ProviderPath
        if ((Split-Path $target -Parent) -ne $expectedParent -or
            (Split-Path $target -Leaf) -notmatch '^\d{8}-\d{6}-\d+$') {
            throw 'Unexpected setup cleanup path.'
        }
        foreach ($path in @($env:ProgramData, $expectedParent, $target)) {
            if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Setup cleanup refuses linked folders.'
            }
        }
        $pending = New-Object 'Collections.Generic.Stack[string]'
        $pending.Push($target)
        while ($pending.Count) {
            foreach ($item in @(Get-ChildItem -LiteralPath $pending.Pop() -Force)) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Setup cleanup refuses linked items.' }
                if (-not $item.FullName.StartsWith($target + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected cleanup child.' }
                if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            }
        }
        Save-SetupLogs -SourceRoot $target -Label 'Setup'
        Remove-Item -LiteralPath $target -Recurse -Force
    } catch {
        Write-Warning "Setup temporary-file cleanup failed: $($_.Exception.Message)"
        exit 1
    }
}
if ($Worker -eq 'Coordinator' -and $script:RunMutex) {
    $script:RunMutex.ReleaseMutex()
    $script:RunMutex.Dispose()
}
if (@($script:Results | Where-Object Status -eq 'Needs attention').Count -gt 0) { exit 1 }
exit 0
