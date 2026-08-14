# Copyright (C) 2026 Anders Syrén
# SPDX-License-Identifier: GPL-3.0-or-later
# MediaPrep MKV Toolkit - GitHub Web Installer
# Windows PowerShell 5.1 compatible, including ConstrainedLanguage environments.
# Non-interactive: suitable for PowerShell console, PowerShell ISE and future package managers.

[CmdletBinding()]
param(
    [string]$Repository = 'anderssyren1967GH/MediaPrep-MKV-Toolkit',
    [string]$InstallPath = 'C:\MediaPrep MKV Toolkit',
    [switch]$KeepDownloadedFiles,
    [switch]$Force,
    [string]$Language = 'system'
)

$ErrorActionPreference = 'Stop'

# The web installer has to bootstrap before the package is available locally.
# After the latest release tag is known it loads the same JSON language resource
# directly from that release. If this is unavailable, en-US fallback text is used.
$script:WebLanguageBase=$null
$script:WebLanguage=$null
function Get-WebProperty([object]$Object,[string]$Name,$Default=$null){if($null-eq$Object){return $Default};$p=$Object.PSObject.Properties[$Name];if($null-eq$p){return $Default};return $p.Value}
function T([string]$Key,[string]$Fallback,[object[]]$FormatArgs=@()){
    $bp=if($script:WebLanguageBase){$script:WebLanguageBase.PSObject.Properties[$Key]}else{$null}
    $base=if($bp -and -not[string]::IsNullOrWhiteSpace([string]$bp.Value)){[string]$bp.Value}else{$Fallback}
    $p=if($script:WebLanguage){$script:WebLanguage.PSObject.Properties[$Key]}else{$null}
    $value=if($p -and -not[string]::IsNullOrWhiteSpace([string]$p.Value)){[string]$p.Value}else{$base}
    $a=@($FormatArgs)
    if($a.Count -gt 0){
        try{return [string]::Format([Globalization.CultureInfo]::CurrentCulture,$value,$a)}catch{}
        try{return [string]::Format([Globalization.CultureInfo]::CurrentCulture,$base,$a)}catch{return $Fallback}
    }
    return $value
}
function Normalize-WebLanguage([string]$Code){
    if([string]::IsNullOrWhiteSpace($Code)){return 'system'}
    $v=$Code.Trim()
    switch($v.ToLowerInvariant()){
        'system'{return 'system'}
        'default'{return 'system'}
        'en'{return 'en-US'}
        'english'{return 'en-US'}
        'en-us'{return 'en-US'}
        'sv'{return 'sv-SE'}
        'swedish'{return 'sv-SE'}
        'svenska'{return 'sv-SE'}
        'sv-se'{return 'sv-SE'}
    }
    try{return ([Globalization.CultureInfo]::GetCultureInfo($v)).Name}catch{return $v}
}
function Get-WebLanguageDocument([string]$Url){try{return (Invoke-RestMethod -Uri $Url -UseBasicParsing -Headers @{'User-Agent'='MediaPrep-WebInstaller'})}catch{return $null}}
function Initialize-WebLanguage([string]$Tag){
    try{
        $baseUrl='https://raw.githubusercontent.com/'+$Repository+'/'+$Tag+'/Languages/mediaprep.en-US.json'
        $script:WebLanguageBase=Get-WebLanguageDocument $baseUrl
        $requested=Normalize-WebLanguage $Language
        if($requested-eq'system'){$requested=[Globalization.CultureInfo]::CurrentUICulture.Name}
        if($requested-ieq'en-US'){$script:WebLanguage=$script:WebLanguageBase;return}
        $selected=Get-WebLanguageDocument ('https://raw.githubusercontent.com/'+$Repository+'/'+$Tag+'/Languages/mediaprep.'+$requested+'.json')
        if($null-eq$selected){
            try{
                $ui=[Globalization.CultureInfo]::GetCultureInfo($requested)
                $contents=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$Repository+'/contents/Languages?ref='+$Tag) -UseBasicParsing -Headers @{'User-Agent'='MediaPrep-WebInstaller';Accept='application/vnd.github+json'}
                foreach($entry in @($contents)){
                    if([string]$entry.name -notmatch '^mediaprep\.(.+)\.json$'){continue}
                    try{$candidateCulture=[Globalization.CultureInfo]::GetCultureInfo($Matches[1]);if($candidateCulture.TwoLetterISOLanguageName -ieq $ui.TwoLetterISOLanguageName){$selected=Get-WebLanguageDocument ([string]$entry.download_url);break}}catch{}
                }
            }catch{}
        }
        if($null-eq$selected){$selected=$script:WebLanguageBase}
        $script:WebLanguage=$selected
    }catch{$script:WebLanguage=$script:WebLanguageBase}
}

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host ('==> ' + $Message) -ForegroundColor Cyan
}

function Stop-Installer {
    param([string]$Message)
    Write-Host ''
    Write-Host (T 'WebInstallerFailed' 'MediaPrep web installation failed.') -ForegroundColor Red
    Write-Host $Message -ForegroundColor Red
    exit 1
}

$apiUrl = 'https://api.github.com/repos/' + $Repository + '/releases/latest'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$random = Get-Random -Minimum 1000 -Maximum 999999
$tempRoot = Join-Path $env:TEMP ('MediaPrep-WebInstall_' + $stamp + '_' + $random)
$zipPath = Join-Path $tempRoot 'MediaPrep-latest.zip'
$extractPath = Join-Path $tempRoot 'Extracted'

try {
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        Stop-Installer (T 'WebInstallerInstallPathEmpty' 'InstallPath cannot be empty.')
    }

    $InstallPath = $InstallPath -replace '^"(.*)"$','$1'

    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

    Write-Step (T 'WebInstallerCheckingLatest' 'Checking the latest MediaPrep release on GitHub')

    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'MediaPrep-WebInstaller'
    }

    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing
    if ($null -eq $release) { Stop-Installer (T 'WebInstallerNoRelease' 'GitHub did not return a release.') }

    $tag = [string]$release.tag_name
    if ([string]::IsNullOrWhiteSpace($tag)) { Stop-Installer (T 'WebInstallerInvalidReleaseTag' 'GitHub did not return a valid release tag.') }

    $version = $tag
    if ($version -match '^[vV](.+)$') { $version = $Matches[1] }

    Initialize-WebLanguage -Tag $tag
    Write-Host ''
    Write-Host (T 'WebInstallerTitle' 'MediaPrep MKV Toolkit - GitHub Web Installer') -ForegroundColor Cyan
    Write-Host (T 'WebInstallerLanguageMode' 'PowerShell language mode: {0}' @([string]$ExecutionContext.SessionState.LanguageMode))
    Write-Host (T 'WebInstallerInstallFolder' 'Installation folder: {0}' @($InstallPath))
    Write-Host (T 'WebInstallerLatestRelease' 'Latest release: {0}' @($tag))

    $expectedName = 'MediaPrep-MKV-Toolkit-' + $version + '.zip'
    $asset = $null

    foreach ($candidate in @($release.assets)) {
        if ([string]$candidate.name -eq $expectedName) {
            $asset = $candidate
            break
        }
    }

    if ($null -eq $asset) {
        foreach ($candidate in @($release.assets)) {
            $name = [string]$candidate.name
            if ($name -match '^MediaPrep-MKV-Toolkit-[0-9]+\.[0-9]+\.[0-9]+\.zip$' -and
                $name -notmatch 'uppdatering|update') {
                $asset = $candidate
                break
            }
        }
    }

    if ($null -eq $asset) {
        Stop-Installer (T 'WebInstallerPackageMissing' 'No packaged MediaPrep ZIP was found in release {0}.' @($tag))
    }

    Write-Step (T 'WebInstallerDownloading' 'Downloading {0}' @([string]$asset.name))
    Invoke-WebRequest -Uri ([string]$asset.browser_download_url) -OutFile $zipPath -UseBasicParsing

    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        Stop-Installer (T 'WebInstallerZipNotDownloaded' 'The release ZIP was not downloaded.')
    }

    $downloaded = Get-Item -LiteralPath $zipPath
    if ($downloaded.Length -le 0) {
        Stop-Installer (T 'WebInstallerZipEmpty' 'The downloaded release ZIP is empty.')
    }

    Write-Host (T 'WebInstallerDownloadedBytes' 'Downloaded bytes: {0}' @([string]$downloaded.Length))

    $digestText = [string]$asset.digest
    if ($digestText -match '^sha256:([0-9a-fA-F]{64})$') {
        Write-Step (T 'WebInstallerVerifyingSha' 'Verifying SHA-256')
        $expectedHash = $Matches[1]
        $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) {
            Stop-Installer (T 'WebInstallerShaFailed' 'SHA-256 verification failed. Expected: {0} Actual: {1}' @($expectedHash,$actualHash))
        }
        Write-Host (T 'WebInstallerShaOk' 'SHA-256: OK') -ForegroundColor Green
    }

    # After integrity verification, remove the Internet-zone marker before extraction when possible.
    try{Unblock-File -LiteralPath $zipPath -ErrorAction SilentlyContinue}catch{}

    Write-Step (T 'WebInstallerExtracting' 'Extracting release package')
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    $launcher = Get-ChildItem -LiteralPath $extractPath -Filter 'Start MediaPrep.cmd' -File -Recurse |
        Select-Object -First 1

    if ($null -eq $launcher) {
        Stop-Installer (T 'WebInstallerLauncherMissing' 'The downloaded package does not contain Start MediaPrep.cmd.')
    }

    $packageRoot = $launcher.Directory.FullName

    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'App\MediaPrep-Start.ps1') -PathType Leaf)) {
        Stop-Installer (T 'WebInstallerStartScriptMissing' 'The downloaded package does not contain App\MediaPrep-Start.ps1.')
    }

    Write-Step (T 'WebInstallerPreparingFolder' 'Preparing installation folder: {0}' @($InstallPath))

    if (-not (Test-Path -LiteralPath $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    }
    else {
        $existing = Get-ChildItem -LiteralPath $InstallPath -Force -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($null -ne $existing -and -not $Force) {
            Stop-Installer (
                (T 'WebInstallerFolderNotEmpty' 'The installation folder already contains files: {0}. Re-run with -Force to update/overwrite program files without deleting unrelated files.' @($InstallPath))
            )
        }
    }

    $writeTest = Join-Path $InstallPath '.mediaprep-install-write-test.tmp'
    try {
        Set-Content -LiteralPath $writeTest -Value 'MediaPrep write test' -Encoding ASCII
        Remove-Item -LiteralPath $writeTest -Force
    }
    catch {
        Stop-Installer (
            (T 'WebInstallerFolderNotWritable' 'The installation folder is not writable: {0}. Choose another folder or run PowerShell as administrator.' @($InstallPath))
        )
    }

    Write-Step (T 'WebInstallerInstalling' 'Installing MediaPrep {0}' @($version))

    $existingMediaPrep=Test-Path -LiteralPath (Join-Path $InstallPath 'App\MediaPrep-Start.ps1') -PathType Leaf
    if($existingMediaPrep -and $Force){
        # Safe in-place program update: preserve Data, preferences, statistics,
        # downloaded tools, logs, queues and media working folders.
        foreach($dirName in @('App','Languages','Installer','Assets')){
            $srcDir=Join-Path $packageRoot $dirName
            $dstDir=Join-Path $InstallPath $dirName
            if(Test-Path -LiteralPath $dstDir -PathType Container){Remove-Item -LiteralPath $dstDir -Recurse -Force}
            Copy-Item -LiteralPath $srcDir -Destination $dstDir -Recurse -Force
        }
        foreach($fileName in @('Start MediaPrep.cmd','README.md','CHANGELOG.md','LICENSE.md','THIRD-PARTY-NOTICES.md')){
            $srcFile=Join-Path $packageRoot $fileName
            if(Test-Path -LiteralPath $srcFile -PathType Leaf){Copy-Item -LiteralPath $srcFile -Destination (Join-Path $InstallPath $fileName) -Force}
        }
        $srcErrorHelper=Join-Path $packageRoot 'Error\Bearbeta felko.cmd'
        if(Test-Path -LiteralPath $srcErrorHelper -PathType Leaf){
            $dstError=Join-Path $InstallPath 'Error'
            if(-not(Test-Path -LiteralPath $dstError -PathType Container)){New-Item -ItemType Directory -Path $dstError -Force|Out-Null}
            Copy-Item -LiteralPath $srcErrorHelper -Destination (Join-Path $dstError 'Bearbeta felko.cmd') -Force
        }
    }
    else {
        Get-ChildItem -LiteralPath $packageRoot -Force | ForEach-Object {
            $destination = Join-Path $InstallPath $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force
        }
    }

    foreach($requiredFolder in @('UnProcessed','Processed','Error','Data','Data\Temp','Data\Downloads','Data\Statistics','Data\ProgramBackups','Loggar','Rapporter','Tools','Tools\FFmpeg','Tools\MKVToolNix','Tools\ToolBackups')){
        $requiredPath=Join-Path $InstallPath $requiredFolder
        if(-not(Test-Path -LiteralPath $requiredPath -PathType Container)){New-Item -ItemType Directory -Path $requiredPath -Force|Out-Null}
    }

    # CMD does not understand an UTF-8 BOM before @echo. Normalize the launchers
    # to plain ASCII/CRLF after installation. This also repairs older release ZIPs.
    foreach($relativeCmd in @('Start MediaPrep.cmd','Error\Bearbeta felko.cmd')) {
        $cmdPath=Join-Path $InstallPath $relativeCmd
        if(Test-Path -LiteralPath $cmdPath -PathType Leaf) {
            $cmdText=Get-Content -LiteralPath $cmdPath -Raw
            Set-Content -LiteralPath $cmdPath -Value $cmdText -Encoding ASCII
        }
    }

    # Best-effort removal of Internet-zone markers from program files only.
    # Runtime/media folders are intentionally excluded.
    try {
        foreach($dirName in @('App','Languages','Installer','Assets','Error')) {
            $dir=Join-Path $InstallPath $dirName
            if(Test-Path -LiteralPath $dir -PathType Container){Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue|Unblock-File -ErrorAction SilentlyContinue}
        }
        foreach($fileName in @('Start MediaPrep.cmd','README.md','CHANGELOG.md','LICENSE.md','THIRD-PARTY-NOTICES.md')) {
            $file=Join-Path $InstallPath $fileName
            if(Test-Path -LiteralPath $file -PathType Leaf){Unblock-File -LiteralPath $file -ErrorAction SilentlyContinue}
        }
    } catch {}

    $installedLauncher = Join-Path $InstallPath 'Start MediaPrep.cmd'
    $installedStartCenter = Join-Path $InstallPath 'App\MediaPrep-Start.ps1'

    if (-not (Test-Path -LiteralPath $installedLauncher -PathType Leaf)) {
        Stop-Installer (T 'WebInstallerVerifyLauncherMissing' 'Installation verification failed: Start MediaPrep.cmd is missing.')
    }

    if (-not (Test-Path -LiteralPath $installedStartCenter -PathType Leaf)) {
        Stop-Installer (T 'WebInstallerVerifyStartMissing' 'Installation verification failed: App\MediaPrep-Start.ps1 is missing.')
    }

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host (T 'WebInstallerInstalled' 'MediaPrep MKV Toolkit {0} installed successfully.' @($version)) -ForegroundColor Green
    Write-Host (T 'WebInstallerInstallFolder' 'Installation folder: {0}' @($InstallPath)) -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ''
    Write-Host (T 'WebInstallerStartWith' 'Start MediaPrep with:') -ForegroundColor Cyan
    Write-Host ('"' + $installedLauncher + '"')
    Write-Host ''
    Write-Host (T 'WebInstallerToolsHint' 'FFmpeg and MKVToolNix can be installed from MediaPrep Settings.')

    if([string]$ExecutionContext.SessionState.LanguageMode -eq 'ConstrainedLanguage') {
        $clmWarning=T 'WebInstallerClmWarning' @'
MediaPrep was installed successfully, but this computer enforces PowerShell ConstrainedLanguage.

MediaPrep requires PowerShell FullLanguage for its graphical interface.
The MediaPrep scripts must be allowed/trusted by your organization's AppLocker or WDAC policy.

Do not troubleshoot FFmpeg, MKVToolNix, or graphics drivers until this PowerShell policy restriction has been resolved.
'@
        Write-Host ''
        Write-Host $clmWarning -ForegroundColor Yellow
        try {
            $msgExe=Join-Path $env:SystemRoot 'System32\msg.exe'
            if(Test-Path -LiteralPath $msgExe -PathType Leaf) {
                & $msgExe $env:USERNAME $clmWarning 2>$null | Out-Null
            }
        } catch {}
    }
}
catch {
    Write-Host ''
    Write-Host (T 'WebInstallerFailed' 'MediaPrep web installation failed.') -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    exit 1
}
finally {
    if ($KeepDownloadedFiles) {
        Write-Host ''
        Write-Host (T 'WebInstallerDownloadsKept' 'Downloaded files kept at: {0}' @($tempRoot))
    }
    else {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
