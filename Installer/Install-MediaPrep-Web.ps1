# MediaPrep MKV Toolkit - GitHub Web Installer
# Windows PowerShell 5.1 compatible, including ConstrainedLanguage environments.

[CmdletBinding()]
param(
    [string]$Repository = 'anderssyren1967GH/MediaPrep-MKV-Toolkit',
    [string]$InstallPath = '',
    [switch]$KeepDownloadedFiles
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host ('==> ' + $Message) -ForegroundColor Cyan
}

function Stop-Installer {
    param([string]$Message)
    Write-Host ''
    Write-Host 'MediaPrep web installation failed.' -ForegroundColor Red
    Write-Host $Message -ForegroundColor Red
    exit 1
}

function Test-Yes {
    param([string]$Value)
    return ($Value -match '^(?i:y|yes|j|ja)$')
}

Write-Host ''
Write-Host 'MediaPrep MKV Toolkit - GitHub Web Installer' -ForegroundColor Cyan
Write-Host ('PowerShell language mode: ' + [string]$ExecutionContext.SessionState.LanguageMode)

$apiUrl = 'https://api.github.com/repos/' + $Repository + '/releases/latest'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$random = Get-Random -Minimum 1000 -Maximum 999999
$tempRoot = Join-Path $env:TEMP ('MediaPrep-WebInstall_' + $stamp + '_' + $random)
$zipPath = Join-Path $tempRoot 'MediaPrep-latest.zip'
$extractPath = Join-Path $tempRoot 'Extracted'

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

    Write-Step 'Checking the latest MediaPrep release on GitHub'

    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'MediaPrep-WebInstaller'
    }

    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing
    if ($null -eq $release) { Stop-Installer 'GitHub did not return a release.' }

    $tag = [string]$release.tag_name
    if ([string]::IsNullOrWhiteSpace($tag)) { Stop-Installer 'GitHub did not return a valid release tag.' }

    $version = $tag
    if ($version -match '^[vV](.+)$') { $version = $Matches[1] }

    Write-Host ('Latest release: ' + $tag)

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
        $available = @($release.assets | ForEach-Object { [string]$_.name }) -join ', '
        Stop-Installer ('No packaged MediaPrep ZIP was found in release ' + $tag + '. Available assets: ' + $available)
    }

    Write-Step ('Downloading ' + [string]$asset.name)
    Invoke-WebRequest -Uri ([string]$asset.browser_download_url) -OutFile $zipPath -UseBasicParsing

    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        Stop-Installer 'The release ZIP was not downloaded.'
    }

    $downloaded = Get-Item -LiteralPath $zipPath
    if ($downloaded.Length -le 0) {
        Stop-Installer 'The downloaded release ZIP is empty.'
    }

    Write-Host ('Downloaded bytes: ' + [string]$downloaded.Length)

    $digestText = [string]$asset.digest
    if ($digestText -match '^sha256:([0-9a-fA-F]{64})$') {
        Write-Step 'Verifying SHA-256'
        $expectedHash = $Matches[1]
        $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) {
            Stop-Installer ('SHA-256 verification failed. Expected: ' + $expectedHash + ' Actual: ' + $actualHash)
        }
        Write-Host 'SHA-256: OK' -ForegroundColor Green
    }

    Write-Step 'Extracting release package'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    $launcher = Get-ChildItem -LiteralPath $extractPath -Filter 'Start MediaPrep.cmd' -File -Recurse |
        Select-Object -First 1

    if ($null -eq $launcher) {
        Stop-Installer 'The downloaded package does not contain Start MediaPrep.cmd.'
    }

    $packageRoot = $launcher.Directory.FullName

    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'App\MediaPrep-Start.ps1') -PathType Leaf)) {
        Stop-Installer 'The downloaded package does not contain App\MediaPrep-Start.ps1.'
    }

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $defaultPath = 'C:\MediaPrep MKV Toolkit'
        Write-Host ''
        Write-Host ('Install MediaPrep MKV Toolkit ' + $version) -ForegroundColor Cyan
        Write-Host ('Default installation folder: ' + $defaultPath)
        Write-Host 'Press Enter to use the default folder, or type another full path.'
        $enteredPath = Read-Host 'Installation folder'
        if ([string]::IsNullOrWhiteSpace($enteredPath)) {
            $InstallPath = $defaultPath
        }
        else {
            $InstallPath = $enteredPath
        }
    }

    $InstallPath = $InstallPath -replace '^"(.*)"$','$1'

    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        Stop-Installer 'No installation folder was selected.'
    }

    Write-Step ('Preparing installation folder: ' + $InstallPath)

    if (Test-Path -LiteralPath $InstallPath) {
        $existing = Get-ChildItem -LiteralPath $InstallPath -Force -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $existing) {
            Write-Host ''
            Write-Host 'The selected installation folder already contains files.' -ForegroundColor Yellow
            Write-Host 'Existing user/runtime files will not be deleted.'
            Write-Host 'Files from the release package with the same names will be replaced.'
            $answer = Read-Host 'Continue? [Y/N]'
            if (-not (Test-Yes $answer)) {
                Stop-Installer 'Installation cancelled by user.'
            }
        }
    }
    else {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    }

    $writeTest = Join-Path $InstallPath '.mediaprep-install-write-test.tmp'
    try {
        Set-Content -LiteralPath $writeTest -Value 'MediaPrep write test' -Encoding ASCII
        Remove-Item -LiteralPath $writeTest -Force
    }
    catch {
        Stop-Installer ('The installation folder is not writable: ' + $InstallPath + '. Try another folder or run PowerShell as administrator.')
    }

    Write-Step ('Installing MediaPrep ' + $version)

    Get-ChildItem -LiteralPath $packageRoot -Force | ForEach-Object {
        $destination = Join-Path $InstallPath $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force
    }

    $installedLauncher = Join-Path $InstallPath 'Start MediaPrep.cmd'
    $installedStartCenter = Join-Path $InstallPath 'App\MediaPrep-Start.ps1'

    if (-not (Test-Path -LiteralPath $installedLauncher -PathType Leaf)) {
        Stop-Installer 'Installation verification failed: Start MediaPrep.cmd is missing.'
    }

    if (-not (Test-Path -LiteralPath $installedStartCenter -PathType Leaf)) {
        Stop-Installer 'Installation verification failed: App\MediaPrep-Start.ps1 is missing.'
    }

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ('MediaPrep MKV Toolkit ' + $version + ' installed successfully.') -ForegroundColor Green
    Write-Host ('Installation folder: ' + $InstallPath) -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Start MediaPrep with:' -ForegroundColor Cyan
    Write-Host ('"' + $installedLauncher + '"')
    Write-Host ''
    Write-Host 'FFmpeg and MKVToolNix can be installed from MediaPrep Settings.'
}
catch {
    Write-Host ''
    Write-Host 'MediaPrep web installation failed.' -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    exit 1
}
finally {
    if ($KeepDownloadedFiles) {
        Write-Host ''
        Write-Host ('Downloaded files kept at: ' + $tempRoot)
    }
    else {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
