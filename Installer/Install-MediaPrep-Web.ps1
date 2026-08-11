# MediaPrep MKV Toolkit - GitHub Web Installer
# Downloads the latest packaged GitHub release and starts the bundled installer.
# Windows PowerShell 5.1 compatible.

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

function Fail {
    param([string]$Message)
    throw $Message
}

# GitHub requires modern TLS. Explicitly enable TLS 1.2 for Windows PowerShell 5.1.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

$apiUrl = "https://api.github.com/repos/$Repository/releases/latest"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('MediaPrep-WebInstall_' + [guid]::NewGuid().ToString('N'))
$zipPath = Join-Path $tempRoot 'MediaPrep-latest.zip'
$extractPath = Join-Path $tempRoot 'Extracted'

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

    Write-Step "Checking the latest MediaPrep release on GitHub"

    $headers = @{
        'Accept'     = 'application/vnd.github+json'
        'User-Agent' = 'MediaPrep-WebInstaller'
    }

    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing

    if ($null -eq $release -or [string]::IsNullOrWhiteSpace([string]$release.tag_name)) {
        Fail 'GitHub did not return a valid published release.'
    }

    $version = ([string]$release.tag_name).TrimStart('v','V')
    Write-Host ("Latest release: {0}" -f $release.tag_name)

    # Select the packaged MediaPrep ZIP uploaded as a release asset.
    # Deliberately exclude update ZIPs and GitHub-generated source archives.
    $expectedName = "MediaPrep-MKV-Toolkit-$version.zip"
    $asset = @($release.assets | Where-Object {
        [string]$_.name -eq $expectedName
    }) | Select-Object -First 1

    if ($null -eq $asset) {
        # Fallback for future naming variations, while still excluding update packages.
        $asset = @($release.assets | Where-Object {
            ([string]$_.name -match '^MediaPrep-MKV-Toolkit-[0-9]+\.[0-9]+\.[0-9]+\.zip$') -and
            ([string]$_.name -notmatch 'uppdatering|update')
        }) | Select-Object -First 1
    }

    if ($null -eq $asset) {
        $available = @($release.assets | ForEach-Object { [string]$_.name }) -join ', '
        Fail ("No packaged MediaPrep ZIP was found in release {0}. Available assets: {1}" -f $release.tag_name,$available)
    }

    Write-Step ("Downloading {0}" -f $asset.name)
    Invoke-WebRequest -Uri ([string]$asset.browser_download_url) -OutFile $zipPath -UseBasicParsing

    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        Fail 'The release ZIP was not downloaded.'
    }

    $downloaded = Get-Item -LiteralPath $zipPath
    if ($downloaded.Length -le 0) {
        Fail 'The downloaded release ZIP is empty.'
    }

    Write-Host ("Downloaded: {0:N1} MB" -f ($downloaded.Length / 1MB))

    # GitHub release assets may expose a SHA-256 digest.
    $digestText = [string]$asset.digest
    if (-not [string]::IsNullOrWhiteSpace($digestText) -and $digestText -match '^sha256:([0-9a-fA-F]{64})$') {
        Write-Step 'Verifying SHA-256'
        $expectedHash = $Matches[1].ToUpperInvariant()
        $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()

        if ($actualHash -ne $expectedHash) {
            Fail ("SHA-256 verification failed.`r`nExpected: {0}`r`nActual:   {1}" -f $expectedHash,$actualHash)
        }

        Write-Host 'SHA-256: OK' -ForegroundColor Green
    }
    else {
        Write-Host 'GitHub did not provide a SHA-256 digest for this asset; continuing without digest verification.' -ForegroundColor Yellow
    }

    Write-Step 'Extracting release package'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    # The release package normally contains one versioned top-level folder.
    # Locate the bundled installer instead of depending on that folder name.
    $installer = Get-ChildItem -LiteralPath $extractPath -Filter 'Install-MediaPrep.ps1' -File -Recurse |
        Where-Object { $_.FullName -match '[\\/]App[\\/]Install-MediaPrep\.ps1$' } |
        Select-Object -First 1

    if ($null -eq $installer) {
        Fail 'The downloaded package does not contain App\Install-MediaPrep.ps1.'
    }

    Write-Step ("Starting MediaPrep {0} installer" -f $version)
    Write-Host ("Installer: {0}" -f $installer.FullName)
    Write-Host ''

    $process = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ('"{0}"' -f $installer.FullName)
        ) `
        -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Fail ("The MediaPrep installer exited with code {0}." -f $process.ExitCode)
    }

    Write-Host ''
    Write-Host ("MediaPrep {0} installer completed." -f $version) -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host 'MediaPrep web installation failed.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {
    if ($KeepDownloadedFiles) {
        Write-Host ''
        Write-Host ("Downloaded files kept at: {0}" -f $tempRoot)
    }
    else {
        try {
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}
