[CmdletBinding()]
param(
    [string]$InstallPath,
    [switch]$NoShortcuts
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# The interactive installer uses WinForms and therefore requires FullLanguage.
# On managed computers, stop with a clear message before Add-Type produces a
# cryptic ConstrainedLanguage error. The GitHub web installer can still copy
# MediaPrep non-interactively, but Start Center itself also requires FullLanguage.
if ([string]$ExecutionContext.SessionState.LanguageMode -eq 'ConstrainedLanguage') {
    $message = @'
MediaPrep MKV Toolkit cannot use the interactive installer on this computer.

PowerShell ConstrainedLanguage is enforced.
MediaPrep's graphical interface requires PowerShell FullLanguage.

Use the GitHub PowerShell web installer for file installation, and ask your
administrator to allow/trust the MediaPrep scripts through AppLocker or WDAC
before trying to start MediaPrep.
'@
    try {
        $msgExe=Join-Path $env:SystemRoot 'System32\msg.exe'
        if(Test-Path -LiteralPath $msgExe -PathType Leaf){& $msgExe $env:USERNAME $message 2>$null|Out-Null}
    } catch {}
    Write-Host $message -ForegroundColor Yellow
    exit 10
}

Add-Type -AssemblyName System.Windows.Forms

$appSource = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceRoot = Split-Path -Parent $appSource
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the folder where MediaPrep MKV Toolkit will be installed.'
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $InstallPath = Join-Path $dialog.SelectedPath 'MediaPrep MKV Toolkit'
}

$InstallPath = [IO.Path]::GetFullPath($InstallPath)
New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null

# Copy only application assets. Runtime media, logs, queues and statistics are never cloned
# when the installer is launched from an already-used MediaPrep installation.
foreach($name in @('App','Languages','Tools','Installer','Assets')){
    $src=Join-Path $sourceRoot $name
    if(Test-Path -LiteralPath $src){Copy-Item -LiteralPath $src -Destination $InstallPath -Recurse -Force}
}
foreach($name in @('Start MediaPrep.cmd','README.md','CHANGELOG.md','LICENSE.md','THIRD-PARTY-NOTICES.md')){
    $src=Join-Path $sourceRoot $name
    if(Test-Path -LiteralPath $src -PathType Leaf){Copy-Item -LiteralPath $src -Destination $InstallPath -Force}
}
$errorTarget=Join-Path $InstallPath 'Error'
New-Item -Path $errorTarget -ItemType Directory -Force|Out-Null
$errorHelper=Join-Path $sourceRoot 'Error\Bearbeta felko.cmd'
if(Test-Path -LiteralPath $errorHelper -PathType Leaf){Copy-Item -LiteralPath $errorHelper -Destination (Join-Path $errorTarget 'Bearbeta felko.cmd') -Force}
$dataTarget=Join-Path $InstallPath 'Data'
New-Item -Path $dataTarget -ItemType Directory -Force|Out-Null
foreach($name in @('config.json','mediaprep.preferences.json')){
    $src=Join-Path (Join-Path $sourceRoot 'Data') $name
    $dst=Join-Path $dataTarget $name
    if((Test-Path -LiteralPath $src -PathType Leaf) -and -not(Test-Path -LiteralPath $dst -PathType Leaf)){Copy-Item -LiteralPath $src -Destination $dst -Force}
}

# Remove Internet-zone markers from the copied MediaPrep program payload.
# This is best-effort and never scans the user's media/runtime folders.
try {
    foreach($dirName in @('App','Languages','Tools','Installer','Assets','Error')) {
        $dir=Join-Path $InstallPath $dirName
        if(Test-Path -LiteralPath $dir -PathType Container){Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue|Unblock-File -ErrorAction SilentlyContinue}
    }
    foreach($fileName in @('Start MediaPrep.cmd','README.md','CHANGELOG.md','LICENSE.md','THIRD-PARTY-NOTICES.md')) {
        $file=Join-Path $InstallPath $fileName
        if(Test-Path -LiteralPath $file -PathType Leaf){Unblock-File -LiteralPath $file -ErrorAction SilentlyContinue}
    }
} catch {}

$requiredFolders = @(
    'UnProcessed','Processed','Data','Data\Temp','Data\Downloads','Loggar','Rapporter',
    'App','Languages','Tools','Tools\FFmpeg','Tools\MKVToolNix','Tools\ToolBackups','Installer','Error','Data\Statistics','Data\ProgramBackups'
)
foreach ($folder in $requiredFolders) {
    New-Item -Path (Join-Path $InstallPath $folder) -ItemType Directory -Force | Out-Null
}

if (-not $NoShortcuts) {
    $shell = New-Object -ComObject WScript.Shell
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\MediaPrep MKV Toolkit.lnk'
    $shortcut = $shell.CreateShortcut($startMenu)
    $shortcut.TargetPath = Join-Path $InstallPath 'Start MediaPrep.cmd'
    $shortcut.WorkingDirectory = $InstallPath
    $shortcut.Description = 'MediaPrep MKV Toolkit'
    $shortcut.Save()
}

[System.Windows.Forms.MessageBox]::Show(
    "MediaPrep MKV Toolkit was installed in:`r`n$InstallPath",
    'Installation complete',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null
