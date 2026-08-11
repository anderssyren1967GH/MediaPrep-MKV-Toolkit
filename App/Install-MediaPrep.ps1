[CmdletBinding()]
param(
    [string]$InstallPath,
    [switch]$NoShortcuts
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
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
foreach($name in @('App','Languages','Tools','Installer')){
    $src=Join-Path $sourceRoot $name
    if(Test-Path -LiteralPath $src){Copy-Item -LiteralPath $src -Destination $InstallPath -Recurse -Force}
}
foreach($name in @('Start MediaPrep.cmd','README.md','CHANGELOG.md','LICENSE.md','THIRD-PARTY-NOTICES.md')){
    $src=Join-Path $sourceRoot $name
    if(Test-Path -LiteralPath $src -PathType Leaf){Copy-Item -LiteralPath $src -Destination $InstallPath -Force}
}
$dataTarget=Join-Path $InstallPath 'Data'
New-Item -Path $dataTarget -ItemType Directory -Force|Out-Null
foreach($name in @('config.json','mediaprep.preferences.json')){
    $src=Join-Path (Join-Path $sourceRoot 'Data') $name
    $dst=Join-Path $dataTarget $name
    if((Test-Path -LiteralPath $src -PathType Leaf) -and -not(Test-Path -LiteralPath $dst -PathType Leaf)){Copy-Item -LiteralPath $src -Destination $dst -Force}
}

$requiredFolders = @(
    'UnProcessed','Processed','Data','Data\Temp','Data\Downloads','Loggar','Rapporter',
    'App','Languages','Tools','Tools\FFmpeg','Tools\MKVToolNix','Tools\ToolBackups','Installer','Error','Data\Statistics'
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
