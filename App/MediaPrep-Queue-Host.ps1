#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JobFile,
    [Parameter(Mandatory=$true)][string]$LogFile
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
$queueScript = Join-Path $scriptDir 'MediaPrep-Queue.ps1'
$logFolder = Split-Path -Parent $LogFile
$transcriptStarted = $false
$job = $null
$verboseLogging = $false
$exitCode = 1
$consoleStatePath = Join-Path (Join-Path $root 'Data') 'queue-console-window.json'

if (-not ('MediaPrep.QueueConsoleNative' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace MediaPrep {
    public static class QueueConsoleNative {
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
}
"@
}

function Initialize-QueueConsoleState {
    try {
        $dataFolder = Split-Path -Parent $consoleStatePath
        if (-not (Test-Path -LiteralPath $dataFolder -PathType Container)) {
            New-Item -Path $dataFolder -ItemType Directory -Force | Out-Null
        }
        $hWnd = [MediaPrep.QueueConsoleNative]::GetConsoleWindow()
        $state = [ordered]@{
            PID = $PID
            Handle = $hWnd.ToInt64()
            Visible = $false
            Updated = (Get-Date).ToString('o')
        }
        $state | ConvertTo-Json | Set-Content -LiteralPath $consoleStatePath -Encoding UTF8
        if ($hWnd -ne [IntPtr]::Zero) {
            [void][MediaPrep.QueueConsoleNative]::ShowWindow($hWnd,0)
        }
    }
    catch {
        # The queue itself must still run even if the optional detail-console state cannot be published.
    }
}

Initialize-QueueConsoleState

function Write-Diagnostic {
    param([string]$Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Write-Host ("[{0}] {1}" -f $stamp, $Message)
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

try {
    if (-not (Test-Path -LiteralPath $logFolder -PathType Container)) {
        New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
    }

    Start-Transcript -LiteralPath $LogFile -Force | Out-Null
    $transcriptStarted = $true
    Write-Diagnostic 'MediaPrep Queue Host startade.'
    Write-Diagnostic ("PowerShell: {0}" -f $PSVersionTable.PSVersion)
    Write-Diagnostic ("64-bit process: {0}" -f [Environment]::Is64BitProcess)
    Write-Diagnostic ("Administratör: {0}" -f (Test-IsAdministrator))
    Write-Diagnostic ("Arbetsmapp: {0}" -f $root)
    Write-Diagnostic ("Jobbfil: {0}" -f $JobFile)
    Write-Diagnostic ("Köskript: {0}" -f $queueScript)
    Write-Diagnostic ("Loggfil: {0}" -f $LogFile)

    if (-not (Test-Path -LiteralPath $JobFile -PathType Leaf)) {
        throw "Jobbfilen hittades inte: $JobFile"
    }

    $job = Get-Content -LiteralPath $JobFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $property = $job.PSObject.Properties['VerboseLogging']
    if ($null -ne $property) {
        $verboseLogging = [bool]$property.Value
    }

    if ($verboseLogging) {
        Write-Diagnostic 'Verbose loggning är aktiverad.'
        Write-Diagnostic ("Kommandorad: {0}" -f [Environment]::CommandLine)
        Write-Diagnostic ("Användare: {0}\\{1}" -f $env:USERDOMAIN, $env:USERNAME)
        Write-Diagnostic ("Dator: {0}" -f $env:COMPUTERNAME)
        Write-Diagnostic 'Jobbinnehåll följer:'
        Write-Host ($job | ConvertTo-Json -Depth 10)
    }

    if (-not (Test-Path -LiteralPath $queueScript -PathType Leaf)) {
        throw "Köskriptet hittades inte: $queueScript"
    }

    Write-Diagnostic 'Läser in och startar MediaPrep-Queue.ps1.'
    $queueResult = & $queueScript -JobFile $JobFile

    if ($null -eq $queueResult) {
        throw 'Köskriptet returnerade ingen statuskod.'
    }

    $resultValues = @($queueResult)
    $lastResult = $resultValues[$resultValues.Count - 1]
    $parsedExitCode = 0
    if (-not [int]::TryParse([string]$lastResult,[ref]$parsedExitCode)) {
        throw ("Köskriptet returnerade en ogiltig statuskod: {0}" -f $lastResult)
    }

    $exitCode = $parsedExitCode
    Write-Diagnostic ("Köskriptet avslutades med exitkod {0}." -f $exitCode)
    if ($verboseLogging) {
        Write-Diagnostic 'Verbose-pausen hanteras av köskriptet innan det returnerar.'
    }
}
catch {
    $exitCode = 1
    Write-Host ''
    Write-Host '================ DETALJERAT STARTFEL ================' -ForegroundColor Red
    Write-Host ("Meddelande       : {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("Feltyp           : {0}" -f $_.Exception.GetType().FullName) -ForegroundColor Red
    Write-Host ("Kategori         : {0}" -f $_.CategoryInfo) -ForegroundColor Red
    Write-Host ("FullyQualifiedId : {0}" -f $_.FullyQualifiedErrorId) -ForegroundColor Red
    if ($_.InvocationInfo) {
        Write-Host ("Skript           : {0}" -f $_.InvocationInfo.ScriptName) -ForegroundColor Red
        Write-Host ("Rad              : {0}" -f $_.InvocationInfo.ScriptLineNumber) -ForegroundColor Red
        Write-Host ("Position         : {0}" -f $_.InvocationInfo.PositionMessage) -ForegroundColor Red
    }
    if ($_.ScriptStackTrace) {
        Write-Host ("Stack            : {0}" -f $_.ScriptStackTrace) -ForegroundColor Red
    }
    if ($_.Exception.InnerException) {
        Write-Host ("Inre fel         : {0}" -f $_.Exception.InnerException.Message) -ForegroundColor Red
    }
    Write-Host '======================================================' -ForegroundColor Red
    Write-Host ("[INFO ] Diagnostik sparades i: {0}" -f $LogFile) -ForegroundColor Yellow

    $noPause = $false
    if ($null -ne $job) {
        $noPauseProperty = $job.PSObject.Properties['NoPause']
        if ($null -ne $noPauseProperty) {
            $noPause = [bool]$noPauseProperty.Value
        }
    }

    if ($verboseLogging -or -not $noPause) {
        Write-Host ''
        [void](Read-Host 'Tryck Enter för att stänga felsökningsfönstret')
    }
}
finally {
    try {
        if (Test-Path -LiteralPath $consoleStatePath -PathType Leaf) {
            $state = Get-Content -LiteralPath $consoleStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([int]$state.PID -eq $PID) { Remove-Item -LiteralPath $consoleStatePath -Force -ErrorAction SilentlyContinue }
        }
    } catch {}
    if ($transcriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
        }
    }
}

exit $exitCode
