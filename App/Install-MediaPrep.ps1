# Copyright (C) 2026 Anders Syrén
# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param(
    [string]$InstallPath,
    [switch]$NoShortcuts,
    [string]$Language = 'system'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$appSource = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceRoot = Split-Path -Parent $appSource
$script:LanguageBase=[pscustomobject]@{}
$script:L=[pscustomobject]@{}
function Get-P([object]$Object,[string]$Name,$Default=$null){if($null-eq$Object){return $Default};$p=$Object.PSObject.Properties[$Name];if($null-eq$p){return $Default};return $p.Value}
function Read-Language([string]$Culture){
    $path=Join-Path (Join-Path $sourceRoot 'Languages') ('mediaprep.'+$Culture+'.json')
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $null}
    try{$doc=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
    if($null-eq$doc -or [string](Get-P $doc 'SchemaVersion' '') -ne '1'){return $null}
    return $doc
}
function Resolve-Language([string]$Code){
    $v = if([string]::IsNullOrWhiteSpace($Code)){'system'}else{$Code.Trim()}
    switch($v.ToLowerInvariant()){
        'en'      { return 'en-US' }
        'english' { return 'en-US' }
        'en-us'   { return 'en-US' }
        'sv'      { return 'sv-SE' }
        'swedish' { return 'sv-SE' }
        'svenska' { return 'sv-SE' }
        'sv-se'   { return 'sv-SE' }
        'system'  { }
        'default' { }
        default {
            if($v -ne 'system' -and $v -ne 'default'){
                try { return ([Globalization.CultureInfo]::GetCultureInfo($v)).Name } catch { return $v }
            }
        }
    }
    $ui=[Globalization.CultureInfo]::CurrentUICulture
    $exact=Read-Language $ui.Name
    if($exact){ return [string](Get-P $exact 'Culture' 'en-US') }
    foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'Languages') -Filter 'mediaprep.*.json' -File -ErrorAction SilentlyContinue)){
        try{
            $doc=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json
            $c=[Globalization.CultureInfo]::GetCultureInfo([string](Get-P $doc 'Culture' ''))
            if($c.TwoLetterISOLanguageName -ieq $ui.TwoLetterISOLanguageName){ return $c.Name }
        }catch{}
    }
    return 'en-US'
}
function T([string]$Key,[string]$Fallback,[object[]]$FormatArgs=@()){
    $bp=if($script:LanguageBase){$script:LanguageBase.PSObject.Properties[$Key]}else{$null}
    $base=if($bp -and -not[string]::IsNullOrWhiteSpace([string]$bp.Value)){[string]$bp.Value}else{$Fallback}
    $p=if($script:L){$script:L.PSObject.Properties[$Key]}else{$null}
    $value=if($p -and -not[string]::IsNullOrWhiteSpace([string]$p.Value)){[string]$p.Value}else{$base}
    $a=@($FormatArgs)
    if($a.Count -gt 0){
        try { return [string]::Format([Globalization.CultureInfo]::CurrentCulture,$value,$a) } catch {}
        try { return [string]::Format([Globalization.CultureInfo]::CurrentCulture,$base,$a) } catch { return $Fallback }
    }
    return $value
}
$script:LanguageBase=Read-Language 'en-US';if($null-eq$script:LanguageBase){$script:LanguageBase=[pscustomobject]@{}}
$resolvedLanguage=Resolve-Language $Language
$script:L=Read-Language $resolvedLanguage;if($null-eq$script:L){$script:L=$script:LanguageBase}

# The interactive installer uses WinForms and therefore requires FullLanguage.
# On managed computers, stop with a clear message before Add-Type produces a
# cryptic ConstrainedLanguage error. The GitHub web installer can still copy
# MediaPrep non-interactively, but Start Center itself also requires FullLanguage.
if ([string]$ExecutionContext.SessionState.LanguageMode -eq 'ConstrainedLanguage') {
    $message = T 'InstallerConstrainedLanguageMessage' @'
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

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = T 'InstallerSelectFolder' 'Select the folder where MediaPrep MKV Toolkit will be installed.'
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
    (T 'InstallerCompleteMessage' 'MediaPrep MKV Toolkit was installed in:`r`n{0}' @($InstallPath)),
    (T 'InstallerCompleteTitle' 'Installation complete'),
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null
