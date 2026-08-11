# MediaPrep MKV Toolkit - GitHub Web Installer
# Windows PowerShell 5.1 compatible, including ConstrainedLanguage environments.

[CmdletBinding()]
param(
    [string]$Repository = 'anderssyren1967GH/MediaPrep-MKV-Toolkit',
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

    $installer = Get-ChildItem -LiteralPath $extractPath -Filter 'Install-MediaPrep.ps1' -File -Recurse |
        Where-Object { $_.FullName -match '[\\/]App[\\/]Install-MediaPrep\.ps1$' } |
        Select-Object -First 1

    if ($null -eq $installer) {
        Stop-Installer 'The downloaded package does not contain App\Install-MediaPrep.ps1.'
    }

    Write-Step ('Starting MediaPrep ' + $version + ' installer')
    $args = '-NoProfile -ExecutionPolicy Bypass -File "' + $installer.FullName + '"'
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Stop-Installer ('The MediaPrep installer exited with code ' + [string]$process.ExitCode)
    }

    Write-Host ''
    Write-Host ('MediaPrep ' + $version + ' installer completed.') -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host 'MediaPrep web installation failed.' -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    exit 1
}
finally {
    if ($KeepDownloadedFiles) {
        Write-Host ('Downloaded files kept at: ' + $tempRoot)
    }
    else {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
