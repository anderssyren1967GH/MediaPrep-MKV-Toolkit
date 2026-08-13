#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JobFile
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:QueueScriptPath=$MyInvocation.MyCommand.Path
$scriptDir=Split-Path -Parent $script:QueueScriptPath
$root=Split-Path -Parent $scriptDir
$mediaPrep=Join-Path $scriptDir 'MediaPrep.ps1'
$script:SettingsFile=Join-Path (Join-Path $root 'Data') 'start-installningar.json'
$script:OriginalConfigText=$null
$script:ConfigWasOverridden=$false
$script:SleepProtectionActive=$false
$script:UpdateProtectionBackup=$null
$script:ElevationAttempted=$false
$script:VerboseLogging=$false
$script:ShutdownRequested=$false
$script:FinalExitCode=1
$script:StopRequestFile=$null
$script:RunStatsPath=Join-Path (Join-Path $root 'Data') 'queue-run-current.json'
$script:CopyStatsPath=Join-Path (Join-Path $root 'Data') 'queue-copy-stats.json'

function Get-P {
    param(
        [object]$Object,
        [string]$Name,
        [object]$DefaultValue
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Test-IsAdministrator {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-ElevatedIfRequired {
    param([object]$Job)

    $requiresAdministrator = [bool](Get-P $Job 'PreventUpdateRestart' $false)
    if (-not $requiresAdministrator -or (Test-IsAdministrator)) {
        return $false
    }

    Write-Host '[INFO ] The selected settings require administrator privileges.' -ForegroundColor Cyan
    Write-Host '[INFO ] Windows is now showing a UAC prompt. Approve it to start the queue.' -ForegroundColor Cyan

    $quotedScript = '"' + $script:QueueScriptPath.Replace('"','\"') + '"'
    $quotedJob = '"' + $JobFile.Replace('"','\"') + '"'
    $argumentLine = '-NoProfile -ExecutionPolicy Bypass -File ' + $quotedScript + ' -JobFile ' + $quotedJob

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'powershell.exe'
    $startInfo.Arguments = $argumentLine
    $startInfo.WorkingDirectory = $root
    $startInfo.UseShellExecute = $true
    $startInfo.Verb = 'runas'

    try {
        [System.Diagnostics.Process]::Start($startInfo) | Out-Null
        return $true
    }
    catch [System.ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -eq 1223) {
            throw 'The UAC prompt was cancelled. The queue was not started because administrator protection could not be enabled.'
        }
        throw
    }
}

function Enable-SleepProtection {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MediaPrepPower {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
'@ -ErrorAction SilentlyContinue
    $ES_CONTINUOUS = [Convert]::ToUInt32('80000000', 16)
    $ES_SYSTEM_REQUIRED = [uint32]1
    $flags = [uint32]($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED)
    $result = [MediaPrepPower]::SetThreadExecutionState($flags)
    if($result -eq 0){throw 'Windows could not enable sleep prevention.'}
    $script:SleepProtectionActive=$true
    Write-Host '[OK   ] Sleep is prevented while the MediaPrep queue is running.' -ForegroundColor Green
}

function Disable-SleepProtection {
    if(-not $script:SleepProtectionActive){return}
    try{
        $ES_CONTINUOUS = [Convert]::ToUInt32('80000000', 16)
        [void][MediaPrepPower]::SetThreadExecutionState([uint32]$ES_CONTINUOUS)
        Write-Host '[INFO ] Normal power-saving settings have been restored.' -ForegroundColor Cyan
    }finally{$script:SleepProtectionActive=$false}
}

function Get-RegistryValueState([string]$Path,[string]$Name){
    if(-not(Test-Path -LiteralPath $Path)){return [pscustomobject]@{PathExists=$false;ValueExists=$false;Value=$null;Kind=$null}}
    $key=Get-Item -LiteralPath $Path
    try{
        $value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $names=@($key.GetValueNames())
        if($names -notcontains $Name){return [pscustomobject]@{PathExists=$true;ValueExists=$false;Value=$null;Kind=$null}}
        return [pscustomobject]@{PathExists=$true;ValueExists=$true;Value=$value;Kind=$key.GetValueKind($Name).ToString()}
    }finally{$key.Close()}
}

function Enable-UpdateRestartProtection {
    if(-not(Test-IsAdministrator)){throw 'Windows Update restart protection requires the queue to run as administrator.'}
    $path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $script:UpdateProtectionBackup=[pscustomobject]@{
        Path=$path
        NoAutoReboot=Get-RegistryValueState $path 'NoAutoRebootWithLoggedOnUsers'
        AUOptions=Get-RegistryValueState $path 'AUOptions'
    }
    if(-not(Test-Path -LiteralPath $path)){New-Item -Path $path -Force|Out-Null}
    New-ItemProperty -Path $path -Name 'NoAutoRebootWithLoggedOnUsers' -PropertyType DWord -Value 1 -Force|Out-Null
    New-ItemProperty -Path $path -Name 'AUOptions' -PropertyType DWord -Value 4 -Force|Out-Null
    Write-Host '[OK   ] Temporary protection against automatic Windows Update restart is enabled.' -ForegroundColor Green
    Write-Host '[INFO ] No Windows Update services were stopped or paused.' -ForegroundColor Cyan
}

function Restore-RegistryValueState([string]$Path,[string]$Name,[object]$State){
    if($State.ValueExists){
        $kind=[Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$State.Kind)
        $key=[Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($Path.Substring(6))
        try{$key.SetValue($Name,$State.Value,$kind)}finally{$key.Close()}
    }else{
        if(Test-Path -LiteralPath $Path){Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue}
    }
}

function Disable-UpdateRestartProtection {
    if($null-eq$script:UpdateProtectionBackup){return}
    try{
        $b=$script:UpdateProtectionBackup
        Restore-RegistryValueState $b.Path 'NoAutoRebootWithLoggedOnUsers' $b.NoAutoReboot
        Restore-RegistryValueState $b.Path 'AUOptions' $b.AUOptions
        if(-not$b.NoAutoReboot.PathExists -and -not$b.AUOptions.PathExists){
            try{if((Get-ChildItem -LiteralPath $b.Path -ErrorAction SilentlyContinue).Count-eq0 -and (Get-Item -LiteralPath $b.Path).Property.Count-eq0){Remove-Item -LiteralPath $b.Path -Force}}catch{}
        }
        Write-Host '[INFO ] Previous Windows Update settings have been restored.' -ForegroundColor Cyan
    }
    finally {
        $script:UpdateProtectionBackup = $null
    }
}

function Build-Args([object]$job,[string]$unc){
    $a=New-Object System.Collections.Generic.List[string]
    switch([string](Get-P $job 'Mode' 'Full')){'AnalyzeOnly'{$a.Add('-AnalyzeOnly')};'EncodeOnly'{$a.Add('-EncodeOnly')}}
    if([bool](Get-P $job 'NoConfirm' $false)){$a.Add('-NoConfirm')}
    $encodingEnabled = [bool](Get-P $job 'EnableEncoding' (Get-P $job 'EncodeRecommended' $true))
    if($encodingEnabled){$a.Add('-EncodeRecommended')}else{$a.Add('-DisableEncoding')}
    if([bool](Get-P $job 'Force' $false)){$a.Add('-Force')}
    if([bool](Get-P $job 'Reanalyze' $false)){$a.Add('-Reanalyze')}
    if([bool](Get-P $job 'RebuildIndex' $false)){$a.Add('-RebuildIndex')}
    if([bool](Get-P $job 'VerboseLogging' $false)){$a.Add('-VerboseLogging')}
    if([bool](Get-P $job 'IgnoreDecodeErrors' $false)){$a.Add('-IgnoreDecodeErrors')}
    if([bool](Get-P $job 'ProcessErrorQueue' $false)){$a.Add('-ProcessErrorQueue')}
    $videoFormats=@((Get-P $job 'VideoFormats' @('.ts','.mp4','.avi','.mpg','.mpeg')) | ForEach-Object {[string]$_})
    if($videoFormats.Count-gt0){$a.Add('-VideoFormats');$a.Add(($videoFormats -join ','))}
    $encoderId=[string](Get-P $job 'EncoderId' 'cpu-libx265')
    if(-not[string]::IsNullOrWhiteSpace($encoderId)){$a.Add('-EncoderId');$a.Add($encoderId)}
    if(-not[string]::IsNullOrWhiteSpace($unc)){
        $a.Add('-ImportFromUnc');$a.Add('-UncSourcePath');$a.Add($unc)
        if([bool](Get-P $job 'DeleteUncAfterSuccess' $true)){$a.Add('-DeleteUncAfterSuccess')}
    }
    $includeList = [string](Get-P $job 'IncludeListPath' '')
    if (-not [string]::IsNullOrWhiteSpace($includeList)) {
        $a.Add('-IncludeListPath')
        $a.Add($includeList)
    }
    $a.Add('-NoPause')
    return $a.ToArray()
}

function ConvertTo-CommandLineArgument {
    param([string]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    return '"' + $Value.Replace('"','\"') + '"'
}

function Invoke-MediaPrepChildProcess {
    param(
        [Parameter(Mandatory=$true)][string[]]$Arguments
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('-NoProfile')
    $parts.Add('-ExecutionPolicy')
    $parts.Add('Bypass')
    $parts.Add('-File')
    $parts.Add((ConvertTo-CommandLineArgument -Value $mediaPrep))

    foreach ($argument in $Arguments) {
        if ($argument -match '^-[A-Za-z]') {
            $parts.Add($argument)
        }
        else {
            $parts.Add((ConvertTo-CommandLineArgument -Value $argument))
        }
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'powershell.exe'
    $startInfo.Arguments = ($parts -join ' ')
    $startInfo.WorkingDirectory = $root
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false

    if ($script:VerboseLogging) {
        Write-Host ('[VERBOSE] Child process: {0} {1}' -f $startInfo.FileName,$startInfo.Arguments) -ForegroundColor DarkGray
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'The MediaPrep process could not be started.'
    }

    $process.WaitForExit()
    $exitCode = [int]$process.ExitCode
    $process.Dispose()
    return $exitCode
}


function Save-JsonUtf8Bom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText(
        $Path,
        $json,
        (New-Object System.Text.UTF8Encoding($true))
    )
}

function Save-RemainingQueue {
    param(
        [Parameter(Mandatory=$true)][object]$Job,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$RemainingQueue
    )

    $Job.UncQueue = @($RemainingQueue)
    if ($null -eq $Job.UncQueue) { $Job.UncQueue = @() }
    Save-JsonUtf8Bom -Path $JobFile -Value $Job
    Save-JsonUtf8Bom -Path $script:SettingsFile -Value $Job

    Write-Host ("[INFO ] Queue list updated. Remaining: {0} folders." -f @($RemainingQueue).Count) -ForegroundColor Cyan
    if (@($RemainingQueue).Count -eq 0) {
        Write-Host '[OK   ] The queue list is now empty.' -ForegroundColor Green
    }
    if ($script:VerboseLogging) {
        foreach ($remaining in $RemainingQueue) {
            Write-Host ("[VERBOSE] Remaining in queue: {0}" -f $remaining) -ForegroundColor DarkGray
        }
    }
}


function Enable-AllInOneConfiguration {
    param([object]$Job)

    $source = [string](Get-P $Job 'TemporarySourceFolder' '')
    $output = [string](Get-P $Job 'TemporaryOutputFolder' '')
    if ([string]::IsNullOrWhiteSpace($source) -or -not (Test-Path -LiteralPath $source -PathType Container)) {
        throw ("All in one source folder is invalid: {0}" -f $source)
    }
    if ([string]::IsNullOrWhiteSpace($output)) {
        throw 'All in one output folder is empty.'
    }
    if (-not (Test-Path -LiteralPath $output -PathType Container)) {
        New-Item -Path $output -ItemType Directory -Force | Out-Null
    }

    $configPath = Join-Path (Join-Path $root 'Data') 'config.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw ("Configuration file is missing: {0}" -f $configPath)
    }

    $script:OriginalConfigText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    $config = $script:OriginalConfigText | ConvertFrom-Json
    $config | Add-Member -NotePropertyName SourceFolder -NotePropertyValue $source -Force
    $config | Add-Member -NotePropertyName OutputFolder -NotePropertyValue $output -Force
    [IO.File]::WriteAllText($configPath,($config | ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($true)))
    $script:ConfigWasOverridden = $true
    Write-Host ("[INFO ] All in one source: {0}" -f $source) -ForegroundColor Cyan
    Write-Host ("[INFO ] All in one output: {0}" -f $output) -ForegroundColor Cyan
}

function Restore-AllInOneConfiguration {
    if (-not $script:ConfigWasOverridden) { return }
    try {
        $configPath = Join-Path (Join-Path $root 'Data') 'config.json'
        [IO.File]::WriteAllText($configPath,$script:OriginalConfigText,(New-Object Text.UTF8Encoding($true)))
        Write-Host '[INFO ] Permanent folder preferences were restored after All in one.' -ForegroundColor Cyan
    }
    finally {
        $script:ConfigWasOverridden = $false
        $script:OriginalConfigText = $null
    }
}

function Remove-EmptySubdirectories {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath
    )

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        return 0
    }

    $removed = 0
    $directories = @(Get-ChildItem -LiteralPath $RootPath -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending)

    foreach ($directory in $directories) {
        try {
            $hasContent = @(Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction Stop).Count -gt 0
            if (-not $hasContent) {
                Remove-Item -LiteralPath $directory.FullName -Force -ErrorAction Stop
                $removed++
                Write-Host ("[INFO ] Removed empty local folder: {0}" -f $directory.FullName) -ForegroundColor DarkCyan
            }
        }
        catch {
            if ($script:VerboseLogging) {
                Write-Host ("[VERBOSE] Could not inspect/remove folder {0}: {1}" -f $directory.FullName,$_.Exception.Message) -ForegroundColor DarkGray
            }
        }
    }

    return $removed
}

function Invoke-LocalEmptyFolderCleanup {
    $total = 0
    $total += Remove-EmptySubdirectories -RootPath (Join-Path $root 'UnProcessed')
    $total += Remove-EmptySubdirectories -RootPath (Join-Path $root 'Processed')
    $total += Remove-EmptySubdirectories -RootPath (Join-Path $root 'Filmer')
    $total += Remove-EmptySubdirectories -RootPath (Join-Path $root 'MKV')

    if ($total -gt 0) {
        Write-Host ("[OK   ] Empty local subfolders removed: {0}" -f $total) -ForegroundColor Green
    }
    elseif ($script:VerboseLogging) {
        Write-Host '[VERBOSE] No empty local subfolders needed to be removed.' -ForegroundColor DarkGray
    }
}

try{
    if(-not(Test-Path -LiteralPath $mediaPrep -PathType Leaf)){throw "MediaPrep.ps1 was not found: $mediaPrep"}
    if(-not(Test-Path -LiteralPath $JobFile -PathType Leaf)){throw "Queue job file was not found: $JobFile"}
    $job=Get-Content -LiteralPath $JobFile -Raw -Encoding UTF8|ConvertFrom-Json
    $configuredSettingsFile=[string](Get-P $job 'SettingsFile' '')
    if (-not [string]::IsNullOrWhiteSpace($configuredSettingsFile)) { $script:SettingsFile=$configuredSettingsFile }
    $workMode=[string](Get-P $job 'WorkMode' 'Queue')
    if ($workMode -eq 'AllInOne') { Enable-AllInOneConfiguration -Job $job }
    $script:VerboseLogging=[bool](Get-P $job 'VerboseLogging' $false)
    $script:StopRequestFile=[string](Get-P $job 'StopRequestFile' '')
    if(-not [string]::IsNullOrWhiteSpace($script:StopRequestFile)){Remove-Item -LiteralPath $script:StopRequestFile -Force -ErrorAction SilentlyContinue}
    if($script:VerboseLogging){
        Write-Host ('[VERBOSE] Queue script: {0}' -f $script:QueueScriptPath) -ForegroundColor DarkGray
        Write-Host ('[VERBOSE] Job file: {0}' -f $JobFile) -ForegroundColor DarkGray
        Write-Host ('[VERBOSE] Administrator: {0}' -f (Test-IsAdministrator)) -ForegroundColor DarkGray
        Write-Host ('[VERBOSE] UNC queue enabled: {0}' -f [bool](Get-P $job 'UncEnabled' $false)) -ForegroundColor DarkGray
        Write-Host ('[VERBOSE] Queue items: {0}' -f @((Get-P $job 'UncQueue' @())).Count) -ForegroundColor DarkGray
    }
    if (Restart-ElevatedIfRequired -Job $job) {
        return [int]0
    }
    if([bool](Get-P $job 'PreventSleep' $true)){Enable-SleepProtection}
    if([bool](Get-P $job 'PreventUpdateRestart' $false)){Enable-UpdateRestartProtection}
    $queue = @((Get-P $job 'UncQueue' @()))
    $localFileQueue = @((Get-P $job 'LocalFileQueue' @()))
    $useQueue = ([bool](Get-P $job 'UncEnabled' $false) -and $workMode -ne 'AllInOne')

    if ($useQueue -and $queue.Count -eq 0) {
        throw 'The UNC queue is enabled but contains no folders.'
    }

    if ($workMode -eq 'AllInOne' -and $localFileQueue.Count -eq 0) {
        throw 'All in one is selected but the file list is empty.'
    }

    if ($useQueue) {
        $items = @($queue)
    }
    else {
        $items = @('')
    }
    $remainingQueue = New-Object System.Collections.Generic.List[string]
    if ($useQueue) { foreach ($queueItem in $queue) { $remainingQueue.Add([string]$queueItem) } }
    $allOk=$true;$failed=New-Object System.Collections.Generic.List[string]
    $start=Get-Date
    Remove-Item -LiteralPath $script:CopyStatsPath -Force -ErrorAction SilentlyContinue
    Save-JsonUtf8Bom -Path $script:RunStatsPath -Value ([pscustomobject][ordered]@{
        StartedLocal=$start.ToString('yyyy-MM-dd HH:mm:ss')
        StartedUtc=$start.ToUniversalTime().ToString('o')
        EndedLocal=''
        EndedUtc=''
        ElapsedSeconds=0
        Status='Running'
    })
    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host ' MediaPrep MKV Toolkit queue' -ForegroundColor Cyan
    Write-Host (" Queue items: {0}" -f @($items).Count) -ForegroundColor Cyan
    Write-Host '================================================================' -ForegroundColor Cyan
    if($script:VerboseLogging){
        Write-Host ('[VERBOSE] Queue start UTC: {0}' -f (Get-Date).ToUniversalTime().ToString('o')) -ForegroundColor DarkGray
        Write-Host ('[VERBOSE] Work mode: {0}; use UNC queue: {1}; items: {2}' -f $workMode,$useQueue,@($items).Count) -ForegroundColor DarkGray
        for($vi=0;$vi -lt @($items).Count;$vi++){Write-Host ('[VERBOSE] Queue item {0}/{1}: {2}' -f ($vi+1),@($items).Count,[string]$items[$vi]) -ForegroundColor DarkGray}
    }
    for($i=0;$i-lt@($items).Count;$i++){
        $unc=[string]$items[$i]
        Write-Host ''
        Write-Host ('='*64) -ForegroundColor DarkCyan
        if($useQueue){Write-Host (" Queue {0}/{1}: {2}" -f ($i+1),@($items).Count,$unc) -ForegroundColor Yellow}
        else{Write-Host ' Local run without UNC queue' -ForegroundColor Yellow}
        Write-Host ('='*64) -ForegroundColor DarkCyan
        if($useQueue -and (-not(Test-Path -LiteralPath $unc -PathType Container))){
            Write-Host ("[ERROR] UNC folder cannot be reached: {0}" -f $unc) -ForegroundColor Red
            $allOk=$false;$failed.Add($unc);continue
        }
        $args=Build-Args $job $unc
        if($script:VerboseLogging){Write-Host ('[VERBOSE] MediaPrep arguments: {0}' -f ($args -join ' | ')) -ForegroundColor DarkGray}
        $code = Invoke-MediaPrepChildProcess -Arguments $args
        Write-Host ("[INFO ] MediaPrep process exited with code {0}." -f $code) -ForegroundColor Cyan
        if($code-ne 0){
            $allOk=$false
            $failedName = if ([string]::IsNullOrWhiteSpace($unc)) { 'Local run' } else { $unc }
            $failed.Add($failedName)
            Write-Host ("[ERROR] Queue item ended with exit code {0}. The next item will continue." -f $code) -ForegroundColor Red
        }
        else {
            Write-Host '[OK   ] Queue item completed.' -ForegroundColor Green

            if ($useQueue) {
                $removeIndex = -1
                for ($queueIndex = 0; $queueIndex -lt $remainingQueue.Count; $queueIndex++) {
                    if ([string]::Equals([string]$remainingQueue[$queueIndex],$unc,[System.StringComparison]::OrdinalIgnoreCase)) {
                        $removeIndex = $queueIndex
                        break
                    }
                }

                if ($removeIndex -ge 0) {
                    $remainingQueue.RemoveAt($removeIndex)
                }
                else {
                    Write-Host ("[WARN ] The completed queue item was not found in the remaining queue: {0}" -f $unc) -ForegroundColor Yellow
                }

                Save-RemainingQueue -Job $job -RemainingQueue @($remainingQueue.ToArray())
            }

            Invoke-LocalEmptyFolderCleanup
        }
    }

    # A final check removes folders that became empty during the final return copy.
    Invoke-LocalEmptyFolderCleanup

    if ($useQueue) {
        if ($allOk) {
            Save-RemainingQueue -Job $job -RemainingQueue @()
        }
        else {
            Save-RemainingQueue -Job $job -RemainingQueue @($remainingQueue.ToArray())
        }
    }

    $elapsed=(Get-Date)-$start
    $ended=Get-Date
    Save-JsonUtf8Bom -Path $script:RunStatsPath -Value ([pscustomobject][ordered]@{
        StartedLocal=$start.ToString('yyyy-MM-dd HH:mm:ss')
        StartedUtc=$start.ToUniversalTime().ToString('o')
        EndedLocal=$ended.ToString('yyyy-MM-dd HH:mm:ss')
        EndedUtc=$ended.ToUniversalTime().ToString('o')
        ElapsedSeconds=[Math]::Round($elapsed.TotalSeconds,1)
        Status=if($allOk){'Completed'}else{'CompletedWithErrors'}
    })
    Write-Host ''
    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host (" Queue completed. Time: {0}" -f $elapsed.ToString('hh\:mm\:ss')) -ForegroundColor Cyan
    if($allOk){Write-Host '[OK   ] All queue items completed without errors.' -ForegroundColor Green}
    else{Write-Host ("[ERROR] Failed queue items: {0}" -f $failed.Count) -ForegroundColor Red;foreach($f in $failed){Write-Host ("  - {0}" -f $f) -ForegroundColor Red}}
    Write-Host '================================================================' -ForegroundColor Cyan

    $shutdown=[bool](Get-P $job 'ShutdownAfterSuccess' $false)
    if($shutdown -and $allOk){
        $script:ShutdownRequested=$true
        Write-Host '[INFO ] Automatic shutdown will be scheduled after protection settings have been restored.' -ForegroundColor Cyan
    }elseif($shutdown -and -not$allOk){
        Write-Host '[WARN ] The computer will not shut down because at least one queue item failed.' -ForegroundColor Yellow
    }
    if(-not[bool](Get-P $job 'NoPause' $false)){
        Write-Host '';[void](Read-Host 'Press Enter to exit')
    }
    if ($allOk) {
        $script:FinalExitCode = 0
    }
    else {
        $script:FinalExitCode = 1
    }
}catch{
    Write-Host ("[ERROR] {0}" -f $_.Exception.Message) -ForegroundColor Red
    if($script:VerboseLogging){
        Write-Host ('[VERBOSE] Error type: {0}' -f $_.Exception.GetType().FullName) -ForegroundColor DarkRed
        Write-Host ('[VERBOSE] Category: {0}' -f $_.CategoryInfo) -ForegroundColor DarkRed
        Write-Host ('[VERBOSE] FullyQualifiedErrorId: {0}' -f $_.FullyQualifiedErrorId) -ForegroundColor DarkRed
        if($_.InvocationInfo){Write-Host ('[VERBOSE] Position: {0}' -f $_.InvocationInfo.PositionMessage) -ForegroundColor DarkRed}
        if($_.ScriptStackTrace){Write-Host ('[VERBOSE] Stack: {0}' -f $_.ScriptStackTrace) -ForegroundColor DarkRed}
    }
    $script:FinalExitCode = 1
    if(-not(Test-Path variable:job) -or -not[bool](Get-P $job 'NoPause' $false)){[void](Read-Host 'Press Enter to exit')}
}
finally {
    if ($script:VerboseLogging) {
        Write-Host ('[VERBOSE] Before restore: FinalExitCode={0}, ShutdownRequested={1}' -f $script:FinalExitCode,$script:ShutdownRequested) -ForegroundColor DarkGray
    }
    Restore-AllInOneConfiguration
    Disable-UpdateRestartProtection
    Disable-SleepProtection
    if ($script:VerboseLogging) {
        Write-Host ('[VERBOSE] After restore: FinalExitCode={0}, ShutdownRequested={1}' -f $script:FinalExitCode,$script:ShutdownRequested) -ForegroundColor DarkGray
    }
}

if ($script:VerboseLogging) {
    Write-Host ''
    Write-Host '================ VERBOSE TROUBLESHOOTING PAUSE ================' -ForegroundColor Yellow
    Write-Host (' Final exit code........: {0}' -f $script:FinalExitCode) -ForegroundColor Yellow
    Write-Host (' Shutdown pending......: {0}' -f $script:ShutdownRequested) -ForegroundColor Yellow
    Write-Host ' Review any red text above before continuing.' -ForegroundColor Yellow
    Write-Host '==========================================================' -ForegroundColor Yellow
    [void](Read-Host 'Press Enter to exit troubleshooting mode')
}

if ($script:ShutdownRequested -and $script:FinalExitCode -eq 0) {
    Write-Host '[WARN ] The computer will shut down in 60 seconds. Run shutdown /a in another window to cancel.' -ForegroundColor Yellow
    & shutdown.exe /s /t 60 /c "The MediaPrep MKV Toolkit queue is complete and all queue items succeeded."
    $shutdownExitCode = $LASTEXITCODE
    if ($shutdownExitCode -eq 0) {
        Write-Host '[OK   ] Windows accepted the shutdown request.' -ForegroundColor Green
    }
    else {
        Write-Host ("[ERROR] Windows rejected the shutdown request. Exit code: {0}" -f $shutdownExitCode) -ForegroundColor Red
        $script:FinalExitCode = 1
    }
}

return [int]$script:FinalExitCode
